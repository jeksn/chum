import AppKit
import ChumCore

/// Applies text transformations to the selection of the frontmost app:
/// captures the selection with a synthetic Cmd+C (borrowing the pasteboard
/// for a moment, restoring it right after), previews transformations in the
/// launcher, and applies the chosen one with a synthetic Cmd+V. The same
/// event-injection approach as the snippet expander and paste-on-select:
/// the launcher panel is non-activating, so the target app stays frontmost
/// and receives the events.
final class TextTransformerController {
    static let shared = TextTransformerController()

    /// A private event source (not exposed as `.private` in this SDK's
    /// overlay) so physical keys held while injecting can't suppress the
    /// synthetic ones, matching the snippet expander.
    private let injectSource = CGEventSource(stateID: CGEventSourceStateID(rawValue: -1)!)
    private let queue = DispatchQueue(label: "chum.texttransformer", qos: .userInitiated)

    private static let copySettle: TimeInterval = 0.15
    private static let panelHideSettle: TimeInterval = 0.08
    private static let pasteSettle: TimeInterval = 0.05
    private static let pasteRestoreInterval: TimeInterval = 0.25
    private static let keyPressInterval: TimeInterval = 0.02

    private init() {}

    /// Reads the focused element's selected text through Accessibility —
    /// the primary capture path. No synthetic events and no pasteboard, so
    /// it works while the launcher panel is open and key (posted keyboard
    /// events would reach Chum, the key-window owner, not the target app).
    /// Nil in apps that don't expose AX selections (Terminal, some Electron
    /// views) — the caller falls back to `captureViaPasteboard`.
    func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return nil }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedValue as! AXUIElement
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let text = selectedValue as? String else { return nil }
        return text
    }

    /// Fallback capture for apps without AX selections: posts a synthetic
    /// Cmd+C, waits for the app to copy, reads the text, then restores the
    /// pasteboard — borrowed, not stolen. The caller MUST hide the launcher
    /// panel first (posted keys go to the app owning the key window) and
    /// reshow it on completion. Nil when the pasteboard's changeCount didn't
    /// move (no selection, or the app ignored the copy). Completion is
    /// called on the main queue.
    func captureViaPasteboard(completion: @escaping (String?) -> Void) {
        ClipboardMonitor.shared.suspendCapture()
        let saved = Self.savedPasteboardContent()
        let changeCountBefore = NSPasteboard.general.changeCount

        // The panel hide (a main-thread orderOut) has to land before the
        // synthetic copy reaches the target app.
        queue.asyncAfter(deadline: .now() + Self.panelHideSettle) { [weak self] in
            guard let self else {
                ClipboardMonitor.shared.resumeCapture()
                completion(nil)
                return
            }
            self.sendKey(keyCode: 8, flags: .maskCommand) // C
            self.queue.asyncAfter(deadline: .now() + Self.copySettle) {
                var text: String?
                if NSPasteboard.general.changeCount != changeCountBefore {
                    text = NSPasteboard.general.string(forType: .string)
                }
                Self.restorePasteboardContent(saved)
                ClipboardMonitor.shared.resumeCapture()
                DispatchQueue.main.async {
                    completion(text)
                }
            }
        }
    }

    /// Replaces the frontmost app's selection with the transformed text:
    /// writes the result to the pasteboard, posts Cmd+V, and restores the
    /// user's clipboard once the paste has landed. Borrowed like the capture.
    func apply(_ transform: TextTransform, to text: String) {
        let result = transform.apply(to: text)
        ClipboardMonitor.shared.suspendCapture()
        let saved = Self.savedPasteboardContent()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)

        queue.asyncAfter(deadline: .now() + Self.pasteSettle) { [weak self] in
            guard let self else {
                ClipboardMonitor.shared.resumeCapture()
                return
            }
            self.sendKey(keyCode: 9, flags: .maskCommand) // V
            // Restore the previous clipboard once the paste has landed;
            // resumeCapture syncs the monitor's changeCount so neither the
            // replacement nor the restore is captured into history.
            self.queue.asyncAfter(deadline: .now() + Self.pasteRestoreInterval) {
                Self.restorePasteboardContent(saved)
                ClipboardMonitor.shared.resumeCapture()
            }
        }
    }

    // MARK: - Pasteboard helpers (same shape as the snippet expander's)

    /// Saves every type currently on the general pasteboard so the override
    /// can be undone without losing non-text content (images, file URLs).
    private static func savedPasteboardContent() -> [(NSPasteboard.PasteboardType, Data)] {
        let pasteboard = NSPasteboard.general
        return (pasteboard.types ?? []).compactMap { type in
            guard let data = pasteboard.data(forType: type) else { return nil }
            return (type, data)
        }
    }

    private static func restorePasteboardContent(_ content: [(NSPasteboard.PasteboardType, Data)]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !content.isEmpty else { return }
        let item = NSPasteboardItem()
        for (type, data) in content {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }

    private func sendKey(keyCode: UInt16, flags: CGEventFlags) {
        let keyDown = CGEvent(keyboardEventSource: injectSource, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Self.keyPressInterval)

        let keyUp = CGEvent(keyboardEventSource: injectSource, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Self.keyPressInterval)
    }
}
