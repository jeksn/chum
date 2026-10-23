import Foundation
import ChumCore
import AppKit

final class ColorStore: ObservableObject {
    private struct StoredColors: Codable {
        var version: Int
        var colors: [SavedColor]
    }

    static let shared = ColorStore()

    @Published private(set) var colors: [SavedColor]

    private init() {
        if let loaded = Self.load() {
            colors = loaded
        } else {
            colors = []
            Self.save(colors)
        }
    }

    /// Saves a picked color. Re-picking a stored hex moves it to the top
    /// (recency ordering like the clipboard) instead of duplicating it.
    func add(hex input: String) {
        guard let hex = ColorFormats.normalize(input) else { return }
        colors.removeAll { $0.hex == hex }
        colors.insert(SavedColor(hex: hex), at: 0)
        if colors.count > 200 {
            colors.removeLast(colors.count - 200)
        }
        save()
    }

    func remove(_ color: SavedColor) {
        colors.removeAll { $0.id == color.id }
        save()
    }

    func clearAll() {
        colors = []
        save()
    }

    /// "#RRGGBB" from an NSColor (sRGB; partially transparent colors are
    /// blended over white — the swatch and hex should agree with what the
    /// user saw under the eyedropper).
    static func hexString(from color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        let alpha = max(0, min(1, srgb.alphaComponent))
        func blend(_ component: CGFloat) -> Int {
            let value = component * alpha + (1 - alpha)
            return Int((max(0, min(1, value)) * 255).rounded())
        }
        return ColorFormats.hexString(
            r: blend(srgb.redComponent),
            g: blend(srgb.greenComponent),
            b: blend(srgb.blueComponent)
        )
    }

    /// NSColor for a stored hex (drawing swatches); black if invalid.
    static func nsColor(for hex: String) -> NSColor {
        guard let rgb = ColorFormats.rgb(fromHex: hex) else { return .black }
        return NSColor(
            srgbRed: CGFloat(rgb.r) / 255,
            green: CGFloat(rgb.g) / 255,
            blue: CGFloat(rgb.b) / 255,
            alpha: 1
        )
    }

    private func save() {
        Self.save(colors)
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chum", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("colors.json")
    }

    private static func load() -> [SavedColor]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredColors.self, from: data) else { return nil }
        return stored.colors
    }

    private static func save(_ colors: [SavedColor]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(StoredColors(version: 1, colors: colors)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
