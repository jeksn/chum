public enum HotkeyDisplay {
    /// Glyph shown in place of the hyper modifiers (⌃⌥⇧⌘) when the symbol
    /// setting is on.
    public static let hyperSymbol = "✦"
    /// Glyph order is fixed by KeyboardShortcuts' modifier description:
    /// control, option, shift, command.
    public static let hyperModifiersDescription = "⌃⌥⇧⌘"

    /// Carbon HIToolbox modifier masks: cmdKey, shiftKey, optionKey, controlKey.
    /// KeyboardShortcuts normalizes `carbonModifiers` to exactly these bits.
    public static let hyperCarbonModifiers = 0x0100 | 0x0200 | 0x0800 | 0x1000

    /**
    Display string for a hotkey description: hyper combos (⌃⌥⇧⌘+key) collapse
    to `✦`+key when `showSymbol` is on; everything else renders unchanged.
    */
    public static func display(description: String, carbonModifiers: Int, showSymbol: Bool) -> String {
        guard showSymbol,
              carbonModifiers == hyperCarbonModifiers,
              description.hasPrefix(hyperModifiersDescription)
        else {
            return description
        }
        return hyperSymbol + description.dropFirst(hyperModifiersDescription.count)
    }
}
