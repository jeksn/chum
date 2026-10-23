import ChumCore

enum HotkeyDisplayTests {
    static func runAll(_ t: TestRunner) {
        let hyper = HotkeyDisplay.hyperCarbonModifiers

        t.run("HotkeyDisplay.hyperComboCollapsesToSymbol") {
            let out = HotkeyDisplay.display(description: "⌃⌥⇧⌘K", carbonModifiers: hyper, showSymbol: true)
            t.check(out == "✦K", "hyper combo should collapse to ✦K, got \(out)")
        }

        t.run("HotkeyDisplay.nonHyperCombosUnchanged") {
            t.check(
                HotkeyDisplay.display(description: "⌘K", carbonModifiers: 0x0100, showSymbol: true) == "⌘K",
                "plain ⌘K should stay unchanged"
            )
            t.check(
                HotkeyDisplay.display(description: "⌃⌥⌘K", carbonModifiers: 0x0100 | 0x0800 | 0x1000, showSymbol: true) == "⌃⌥⌘K",
                "three-modifier combo should stay unchanged"
            )
            t.check(
                HotkeyDisplay.display(description: "⇧K", carbonModifiers: 0x0200, showSymbol: true) == "⇧K",
                "shift-only combo should stay unchanged"
            )
        }

        t.run("HotkeyDisplay.symbolOffRendersFullModifiers") {
            let out = HotkeyDisplay.display(description: "⌃⌥⇧⌘K", carbonModifiers: hyper, showSymbol: false)
            t.check(out == "⌃⌥⇧⌘K", "symbol off should render full modifiers, got \(out)")
        }

        t.run("HotkeyDisplay.mismatchedDescriptionUnchanged") {
            let out = HotkeyDisplay.display(description: "K", carbonModifiers: hyper, showSymbol: true)
            t.check(out == "K", "description without the modifier prefix should stay unchanged, got \(out)")
        }
    }
}
