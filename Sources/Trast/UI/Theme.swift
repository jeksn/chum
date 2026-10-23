import SwiftUI

/// The Koltrast (Eurasian blackbird) accent — the app is named after the
/// Swedish name for the bird. The amber (#F59F00, sampled from the app
/// icon's beak and eye ring) tints exactly one element: the bird logo in
/// the launcher search bar. Everything else is native — system accent for
/// selection/hover, secondary for glyphs.
enum Theme {
    /// Beak / eye-ring amber.
    static let beak = Color(red: 245 / 255, green: 159 / 255, blue: 0)
}
