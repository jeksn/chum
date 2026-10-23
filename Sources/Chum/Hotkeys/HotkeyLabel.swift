import KeyboardShortcuts
import ChumCore

extension KeyboardShortcuts.Shortcut {
    /// Chum's display string for the shortcut: hyper combos (⌃⌥⇧⌘+key)
    /// render as ✦+key when the hyper symbol setting is on.
    var hyperDescription: String {
        HotkeyDisplay.display(
            description: description,
            carbonModifiers: carbonModifiers,
            showSymbol: AppSettings.hyperSymbol
        )
    }
}
