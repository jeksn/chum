import Foundation

/// A color saved from the Color Picker tool. The hex string is the single
/// source of truth, stored normalized as "#RRGGBB" (uppercase); every
/// display format (rgb, hsl) derives from it.
public struct SavedColor: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var hex: String
    public var createdAt: Date

    public init(id: UUID = UUID(), hex: String, createdAt: Date = Date()) {
        self.id = id
        self.hex = hex
        self.createdAt = createdAt
    }
}

/// Pure hex/rgb/hsl conversions for the Color Picker tool — no AppKit, so
/// everything here is unit-testable from the harness.
public enum ColorFormats {
    /// Normalizes user-entered hex ("f59f00", "#f59f00") to "#F59F00".
    /// Returns nil for anything that isn't a 6-digit hex RGB string.
    public static func normalize(_ input: String) -> String? {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + hex.uppercased()
    }

    /// Parses a (normalized or bare) hex string into 0-255 components.
    public static func rgb(fromHex hex: String) -> (r: Int, g: Int, b: Int)? {
        guard let normalized = normalize(hex) else { return nil }
        let digits = normalized.dropFirst()
        guard let r = Int(digits.prefix(2), radix: 16),
              let g = Int(digits.dropFirst(2).prefix(2), radix: 16),
              let b = Int(digits.dropFirst(4).prefix(2), radix: 16) else { return nil }
        return (r, g, b)
    }

    /// "#RRGGBB" from 0-255 components (values are clamped).
    public static func hexString(r: Int, g: Int, b: Int) -> String {
        func clamp(_ v: Int) -> Int { min(max(v, 0), 255) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// "rgb(245, 159, 0)"
    public static func rgbString(r: Int, g: Int, b: Int) -> String {
        "rgb(\(r), \(g), \(b))"
    }

    /// "hsl(37, 100%, 48%)" — H in degrees, S and L in percent, rounded.
    public static func hslString(r: Int, g: Int, b: Int) -> String {
        let hue = hueDegrees(r: r, g: g, b: b)
        let sat = saturationPercent(r: r, g: g, b: b)
        let light = luminancePercent(r: r, g: g, b: b)
        return "hsl(\(hue), \(sat)%, \(light)%)"
    }

    static func hueDegrees(r: Int, g: Int, b: Int) -> Int {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        guard maxC != minC else { return 0 }
        let delta = maxC - minC
        let hue: Double
        switch maxC {
        case rf:
            hue = (gf - bf) / delta
        case gf:
            hue = (bf - rf) / delta + 2
        default:
            hue = (rf - gf) / delta + 4
        }
        let degrees = hue * 60
        // The red sector produces negatives when green < blue; wrap into 0..<360.
        return (Int(degrees.rounded()) % 360 + 360) % 360
    }

    static func saturationPercent(r: Int, g: Int, b: Int) -> Int {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        guard maxC != minC else { return 0 }
        let light = (maxC + minC) / 2
        let divisor = 1 - abs(2 * light - 1)
        guard divisor > 0 else { return 0 }
        return Int(((maxC - minC) / divisor * 100).rounded())
    }

    static func luminancePercent(r: Int, g: Int, b: Int) -> Int {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        return Int(((max(rf, gf, bf) + min(rf, gf, bf)) / 2 * 100).rounded())
    }
}

public extension SavedColor {
    /// 0-255 components of the stored hex; nil if the hex is invalid
    /// (shouldn't happen — the store normalizes on save).
    var rgb: (r: Int, g: Int, b: Int)? {
        ColorFormats.rgb(fromHex: hex)
    }

    var rgbText: String {
        guard let rgb else { return hex }
        return ColorFormats.rgbString(r: rgb.r, g: rgb.g, b: rgb.b)
    }

    var hslText: String {
        guard let rgb else { return hex }
        return ColorFormats.hslString(r: rgb.r, g: rgb.g, b: rgb.b)
    }
}
