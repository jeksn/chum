import TrastCore
import Foundation

enum SavedColorTests {
    static func runAll(_ t: TestRunner) {
        t.run("ColorFormats.normalize") {
            t.check(ColorFormats.normalize("f59f00") == "#F59F00", "bare hex")
            t.check(ColorFormats.normalize("#f59f00") == "#F59F00", "prefixed hex")
            t.check(ColorFormats.normalize("  #F59F00 \n") == "#F59F00", "surrounding whitespace trimmed")
            t.check(ColorFormats.normalize("#FFF") == nil, "3-digit shorthand rejected")
            t.check(ColorFormats.normalize("#GGHHII") == nil, "non-hex digits rejected")
            t.check(ColorFormats.normalize("") == nil, "empty rejected")
        }

        t.run("ColorFormats.rgbRoundTrip") {
            guard let amber = ColorFormats.rgb(fromHex: "#F59F00") else {
                t.check(false, "amber parse failed")
                return
            }
            t.check(amber == (r: 245, g: 159, b: 0), "amber, got \(amber)")
            t.check(ColorFormats.rgb(fromHex: "#000000")?.r == 0, "black")
            t.check(ColorFormats.rgb(fromHex: "#FFFFFF")?.b == 255, "white")
            t.check(ColorFormats.rgb(fromHex: "nonsense") == nil, "invalid hex")
        }

        t.run("ColorFormats.hexString") {
            t.check(ColorFormats.hexString(r: 245, g: 159, b: 0) == "#F59F00", "beak amber")
            t.check(ColorFormats.hexString(r: 0, g: 0, b: 0) == "#000000", "black")
            t.check(ColorFormats.hexString(r: 300, g: -5, b: 26) == "#FF001A", "clamps out-of-range components")
        }

        t.run("ColorFormats.rgbString") {
            t.check(ColorFormats.rgbString(r: 245, g: 159, b: 0) == "rgb(245, 159, 0)", "format")
        }

        t.run("ColorFormats.hslString") {
            // #F59F00: hue ~39deg, fully saturated, mid lightness.
            t.check(ColorFormats.hslString(r: 245, g: 159, b: 0) == "hsl(39, 100%, 48%)", "amber, got \(ColorFormats.hslString(r: 245, g: 159, b: 0))")
            // Grays are saturated 0% with a zero hue.
            t.check(ColorFormats.hslString(r: 128, g: 128, b: 128) == "hsl(0, 0%, 50%)", "mid gray, got \(ColorFormats.hslString(r: 128, g: 128, b: 128))")
            // Pure blue sits at 240deg; the red sector wraps negatives
            // (magenta-leaning colors) into 0..<360.
            t.check(ColorFormats.hslString(r: 255, g: 0, b: 0) == "hsl(0, 100%, 50%)", "pure red, got \(ColorFormats.hslString(r: 255, g: 0, b: 0))")
            t.check(ColorFormats.hslString(r: 0, g: 0, b: 255) == "hsl(240, 100%, 50%)", "pure blue, got \(ColorFormats.hslString(r: 0, g: 0, b: 255))")
            t.check(ColorFormats.hslString(r: 255, g: 0, b: 255) == "hsl(300, 100%, 50%)", "magenta, got \(ColorFormats.hslString(r: 255, g: 0, b: 255))")
        }

        t.run("SavedColor.codableRoundTrip") {
            let color = SavedColor(hex: "#F59F00")
            guard let data = try? JSONEncoder().encode(color),
                  let decoded = try? JSONDecoder().decode(SavedColor.self, from: data) else {
                t.check(false, "round trip failed")
                return
            }
            t.check(decoded.id == color.id, "id")
            t.check(decoded.hex == "#F59F00", "hex")
            t.check(decoded.createdAt == color.createdAt, "createdAt")
        }

        t.run("SavedColor.derivedText") {
            let color = SavedColor(hex: "#F59F00")
            t.check(color.rgbText == "rgb(245, 159, 0)", "rgbText, got \(color.rgbText)")
            t.check(color.hslText == "hsl(39, 100%, 48%)", "hslText, got \(color.hslText)")
            t.check(SavedColor(hex: "broken").rgbText == "broken", "invalid hex falls back to stored string")
        }
    }
}
