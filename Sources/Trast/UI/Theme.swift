import SwiftUI

/// The Koltrast (Eurasian blackbird) accent — the app is named after the
/// Swedish name for the bird. The amber (#F59F00, sampled from the app
/// icon's beak and eye ring) is a small fixed accent on icons and badges
/// only; interactive states (selection, hover) stay on the system accent
/// color so the launcher reads native.
enum Theme {
    /// Beak / eye-ring amber.
    static let beak = Color(red: 245 / 255, green: 159 / 255, blue: 0)
}
