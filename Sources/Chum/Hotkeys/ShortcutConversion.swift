import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Shortcut {
    var swiftUIShortcut: KeyboardShortcut? {
        guard let key else { return nil }

        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }

        guard let equivalent = key.toKeyEquivalent else { return nil }
        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }
}

private extension KeyboardShortcuts.Key {
    var toKeyEquivalent: KeyEquivalent? {
        let mapping: [Int: Character] = [
            0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h", 0x05: "g",
            0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v", 0x0B: "b",
            0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r",
            0x10: "y", 0x11: "t",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "o", 0x20: "u", 0x21: "[",
            0x22: "i", 0x23: "p",
            0x25: "l", 0x26: "j", 0x27: "'", 0x28: "k",
            0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "n", 0x2E: "m", 0x2F: ".",
            0x32: "`",
        ]

        switch rawValue {
        case 0x24: return .return
        case 0x30: return .tab
        case 0x31: return .space
        case 0x33: return .delete
        case 0x35: return .escape
        case 0x75: return .deleteForward
        case 0x73: return .home
        case 0x77: return .end
        case 0x74: return .pageUp
        case 0x79: return .pageDown
        case 0x7B: return .leftArrow
        case 0x7C: return .rightArrow
        case 0x7D: return .downArrow
        case 0x7E: return .upArrow
        default:
            if let char = mapping[rawValue] {
                return KeyEquivalent(char)
            }
            return nil
        }
    }
}
