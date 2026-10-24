import SwiftUI

/// The Chum landing-page palette — Tailwind's default blue. `chumBlue`
/// (blue-400, #60A5FA) is the primary accent: pure blue-500 reads too
/// saturated on dark surfaces. Row/bubble tints use `chumBlueDark` at low
/// opacity; bright accents (labels, dots, glows) use `chumBlueBright`.
extension Color {
    static let chumBlue = Color(red: 0.376, green: 0.647, blue: 0.980) // #60A5FA
    static let chumBlueDark = Color(red: 0.231, green: 0.510, blue: 0.965) // #3B82F6
    static let chumBlueBright = Color(red: 0.576, green: 0.773, blue: 0.992) // #93C5FD
}
