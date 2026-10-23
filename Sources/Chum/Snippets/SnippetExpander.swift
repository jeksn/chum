import AppKit
import CoreGraphics
import Foundation
import ChumCore

final class SnippetExpander {
    static let shared = SnippetExpander()

    /// Marks events we inject so the tap ignores its own output instead of
    /// feeding expansion text back into the keystroke buffer.
    private static let syntheticTag: Int64 = 0x5770_536E_6970
    /// Pause before selecting the keyword: lets the final physical keystroke
    /// finish so synthetic events never race real ones still in flight.
    private static let settleInterval: TimeInterval = 0.03
    /// Gap between a synthetic keyDown and its keyUp: zero-length presses get
    /// filtered as noise by some apps.
    private static let keyPressInterval: TimeInterval = 0.006
    /// Pacing between selection keystrokes. Unlike text-generating events
    /// (which coalesce and drop characters below ~12ms), plain arrow-key
    /// events are safe to post almost back-to-back; the gap only needs to
    /// keep the presses distinct. This matters for feel: the selection is
    /// built one Shift+Left per keyword character, and at ~12ms apiece the
    /// highlight visibly swept right-to-left before the paste for longer
    /// keywords ("!today" crawled for ~110ms).
    private static let selectionInterval: TimeInterval = 0.002
    /// Pause between the selection phase and the paste so the app has
    /// processed the selection before the paste replaces it.
    private static let phaseInterval: TimeInterval = 0.015
    /// How long the expansion stays on the pasteboard before the user's
    /// clipboard content is restored.
    private static let clipboardRestoreInterval: TimeInterval = 0.25

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var clickMonitor: Any?
    private var appChangeObserver: NSObjectProtocol?
    private let injectQueue = DispatchQueue(label: "com.chum.snippet.inject", qos: .userInteractive)
    // kCGEventSourceStatePrivate is not exposed as a Swift enum case; its raw
    // value is ~0. A private source isolates synthetic events from the shared
    // HID state so physical keys held during expansion can't suppress them.
    private let injectSource = CGEventSource(stateID: CGEventSourceStateID(rawValue: -1)!)

    private init() {}

    var isRunning: Bool { eventTap != nil }

    func start() {
        guard AppSettings.snippetsEnabled else { return }
        guard eventTap == nil else { return }
        guard ensureInputMonitoringPermission() else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let expander = Unmanaged<SnippetExpander>.fromOpaque(userInfo).takeUnretainedValue()
            return expander.handleEvent(event) ? Unmanaged.passRetained(event) : nil
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        installClickMonitor()
        observeAppChanges()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        if let appChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appChangeObserver)
        }
        eventTap = nil
        runLoopSource = nil
        clickMonitor = nil
        appChangeObserver = nil
        buffer = ""
    }

    /// Clicking into another field invalidates the typed context.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.buffer = ""
        }
    }

    /// Switching apps invalidates the typed context.
    private func observeAppChanges() {
        guard appChangeObserver == nil else { return }
        appChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.buffer = ""
        }
    }

    func restart() {
        stop()
        start()
    }

    private func ensureInputMonitoringPermission() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        CGRequestListenEventAccess()
        return CGPreflightListenEventAccess()
    }

    private func handleEvent(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag {
            return true
        }

        // Keystrokes landing in Chum's own UI (launcher search, settings
        // fields) never expand: editing a snippet's keyword in Settings must
        // not fire the snippet. Our panel/windows are the key window only
        // while the user is actually typing into them.
        if NSApp.keyWindow != nil {
            buffer = ""
            return true
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            // Modified keystrokes (paste, select all, shortcuts) never produce
            // contiguous typed text.
            buffer = ""
            return true
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case 36, 76:
            buffer = ""
            return true
        case 53:
            buffer = ""
            return true
        case 48:
            buffer = ""
            return true
        case 49:
            buffer = ""
            return true
        case 51:
            if !buffer.isEmpty { buffer.removeLast() }
            return true
        default:
            break
        }

        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let maxLen = chars.count
        event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLength, unicodeString: &chars)

        // Keys that produce no text (arrows, function keys, Home/End, forward
        // delete) mean the cursor moved: the typed text is no longer contiguous.
        guard actualLength > 0 else {
            buffer = ""
            return true
        }

        let charString = String(utf16CodeUnits: chars, count: actualLength)
        guard let char = charString.first else {
            buffer = ""
            return true
        }

        if char.isWhitespace {
            buffer = ""
            return true
        }

        buffer.append(char)

        if let match = matchingSnippet() {
            buffer = ""
            expand(keyword: match.keyword, into: match.content)
        }

        return true
    }

    private func matchingSnippet() -> Snippet? {
        let snippets = SnippetStore.shared.validSnippets
        for snippet in snippets where snippet.keyword == buffer {
            return snippet
        }
        return nil
    }

    /// Terminals turn arrow keys into escape sequences instead of moving the
    /// cursor, so the Shift+Left selection sweep leaks bytes into the buffer
    /// ("!zsh" -> "!zshDDDD…"). They get the backspace path instead — which
    /// is safe there, since a shell prompt has no autocomplete suggestion for
    /// a backspace to eat (the reason the backspace path was abandoned for
    /// browsers).
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
    ]

    private static var frontmostIsTerminal: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            .map(terminalBundleIDs.contains) ?? false
    }

    /// Expands in two phases: erase the typed keyword, then paste the
    /// expansion in one shot.
    ///
    /// In normal apps the erase is a Shift+Left selection sweep; in terminals
    /// it's backspaces. Paste (Cmd+V) instead of typing the text char-by-char:
    /// - Address bars (Chrome/Safari omnibox) inline-autocomplete what you
    ///   type; the gray suggestion is a live selection, so the first backspace
    ///   eats the suggestion instead of a typed character and the keyword
    ///   leaves residue ("!in" -> "!https://…"). The selection covers the
    ///   autocomplete too and the paste replaces the whole thing.
    /// - Typing synthetically must be paced ~12ms/char (below that, events
    ///   coalesce and characters drop), so long expansions streamed visibly
    ///   for hundreds of milliseconds. A paste lands in a single frame.
    private func expand(keyword: String, into expansion: String) {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        let resolved = SnippetTemplate.resolve(expansion, clipboardContent: clipboard)

        // The expansion takes over the pasteboard for a moment; keep the
        // transient text out of the clipboard history.
        ClipboardMonitor.shared.suspendCapture()

        injectQueue.asyncAfter(deadline: .now() + Self.settleInterval) { [weak self] in
            guard let self else {
                ClipboardMonitor.shared.resumeCapture()
                return
            }

            if Self.frontmostIsTerminal {
                for _ in 0..<keyword.count {
                    self.sendKey(keyCode: 51, flags: [])
                    Thread.sleep(forTimeInterval: Self.selectionInterval)
                }
            } else {
                for _ in 0..<keyword.count {
                    self.sendKey(keyCode: 123, flags: .maskShift)
                    Thread.sleep(forTimeInterval: Self.selectionInterval)
                }
            }

            Thread.sleep(forTimeInterval: Self.phaseInterval)

            let saved = Self.savedPasteboardContent()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(resolved, forType: .string)
            self.sendKey(keyCode: 9, flags: .maskCommand)

            // Restore the previous clipboard once the paste has landed;
            // resumeCapture syncs the monitor's changeCount so neither the
            // expansion nor the restore is re-captured into the history.
            self.injectQueue.asyncAfter(deadline: .now() + Self.clipboardRestoreInterval) {
                Self.restorePasteboardContent(saved)
                ClipboardMonitor.shared.resumeCapture()
            }
        }
    }

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
        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Self.keyPressInterval)

        let keyUp = CGEvent(keyboardEventSource: injectSource, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
        keyUp?.post(tap: .cghidEventTap)
    }
}
