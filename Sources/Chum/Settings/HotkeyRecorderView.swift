import AppKit
import KeyboardShortcuts
import SwiftUI
import ChumCore

/// Chum's own hotkey recorder. Stores through the same
/// `KeyboardShortcuts.setShortcut`/`getShortcut` API as the package's
/// `Recorder`, but renders hyper combos (⌃⌥⇧⌘+key) as ✦+key and never
/// touches the package's resource bundle (whose `Bundle.module` path is
/// patched for packaged builds).
struct HotkeyRecorderView<Label: View>: View {
    let name: KeyboardShortcuts.Name
    let label: Label

    init(name: KeyboardShortcuts.Name, @ViewBuilder label: () -> Label) {
        self.name = name
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            HotkeyRecorderRepresentable(name: name)
        } label: {
            label
        }
    }
}

extension HotkeyRecorderView where Label == Text {
    init(_ title: String, name: KeyboardShortcuts.Name) {
        self.init(name: name) { Text(title) }
    }
}

private struct HotkeyRecorderRepresentable: NSViewRepresentable {
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> HotkeyRecorderField {
        HotkeyRecorderField(name: name)
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.shortcutName = name
    }
}

/// A non-editable search field that records keyboard shortcuts while it is
/// the first responder. Mirrors `KeyboardShortcuts.RecorderCocoa` rules:
/// bare Tab blurs and bubbles up, bare Escape cancels, bare Backspace/Delete
/// clears the shortcut, shift-only (or modifier-less) combos beep.
final class HotkeyRecorderField: NSSearchField {
    private let minimumWidth: Double = 130
    /// Delayed until the view is in a window so the recorder does not steal
    /// initial focus in the settings form.
    private var canBecomeKey = false
    /// Our own reference to the cell's cancel button so its click action and
    /// visibility can be managed without the cell recreating it.
    private var cancelButtonCell: NSButtonCell?

    var shortcutName: KeyboardShortcuts.Name {
        didSet {
            guard shortcutName != oldValue else { return }
            refresh()
        }
    }

    init(name: KeyboardShortcuts.Name) {
        self.shortcutName = name
        super.init(frame: .zero)

        isEditable = false
        isSelectable = false
        alignment = .center
        placeholderString = "Record Shortcut"
        focusRingType = .exterior
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)

        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        if let cancel = (cell as? NSSearchFieldCell)?.cancelButtonCell {
            cancel.target = self
            cancel.action = #selector(clearShortcut)
            cancelButtonCell = cancel
        }

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { canBecomeKey }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [self] in
            canBecomeKey = true
        }
    }

    override func becomeFirstResponder() -> Bool {
        let should = super.becomeFirstResponder()
        guard should else { return should }
        placeholderString = "Press Shortcut"
        return should
    }

    override func resignFirstResponder() -> Bool {
        let should = super.resignFirstResponder()
        if should {
            placeholderString = "Record Shortcut"
        }
        return should
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width = minimumWidth
        return size
    }

    /// Menu key equivalents are matched before `keyDown` reaches the first
    /// responder, so recording input is consumed here instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              window?.firstResponder === self
        else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        // Bare Tab blurs and bubbles so keyboard navigation keeps working.
        if modifiers.isEmpty && event.keyCode == 0x30 {
            window?.makeFirstResponder(nil)
            super.keyDown(with: event)
            return
        }

        // Bare Escape cancels recording.
        if modifiers.isEmpty && event.keyCode == 0x35 {
            window?.makeFirstResponder(nil)
            return
        }

        // Bare Backspace/Delete clears the shortcut.
        if modifiers.isEmpty && (event.keyCode == 0x33 || event.keyCode == 0x75) {
            clearShortcut()
            return
        }

        // Shift alone (or no modifier at all) is not a valid shortcut, except
        // with function keys.
        guard !modifiers.subtracting(.shift).isEmpty || Self.isFunctionKey(event.keyCode) else {
            NSSound.beep()
            return
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return
        }

        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        stringValue = shortcut.hyperDescription
        showsCancelButton = true
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {}

    @objc private func clearShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: shortcutName)
        stringValue = ""
        showsCancelButton = false
    }

    private func refresh() {
        let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName)
        stringValue = shortcut?.hyperDescription ?? ""
        showsCancelButton = shortcut != nil
    }

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButtonCell : nil }
    }

    private static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        // kVK_F1 ... kVK_F19
        let functionKeyCodes: Set<UInt16> = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F,
            0x69, 0x6B, 0x71, 0x6A, 0x72, 0x73, 0x74,
        ]
        return functionKeyCodes.contains(keyCode)
    }
}
