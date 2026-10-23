import Foundation

/// Launcher row favorites, pinned to the top of the recent-activity view.
/// Keyed by `LauncherItem.id` — the same stable strings (hotkey names,
/// bundle IDs, action IDs) the UsageTracker records — so favorites survive
/// relaunches.
final class FavoritesStore {
    static let shared = FavoritesStore()

    private static let key = "launcherFavorites"
    private(set) var ids: Set<String>

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: Self.key)
    }
}
