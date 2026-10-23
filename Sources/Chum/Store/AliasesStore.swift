import Foundation
import Combine

/// User-defined launcher aliases (item id → alternate name): "sys" can
/// surface System Settings first. Stored in UserDefaults; changes post a
/// debounced notification so the launcher re-indexes without rebuilding per
/// keystroke in the modal's alias field.
final class AliasesStore: ObservableObject {
    static let shared = AliasesStore()
    static let aliasesDidUpdate = Notification.Name("ChumAliasesDidUpdate")

    private static let storageKey = "launcherAliases"
    private var debounce: DispatchWorkItem?

    @Published private(set) var aliases: [String: String]

    private init() {
        aliases = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    func alias(for id: String) -> String {
        aliases[id] ?? ""
    }

    /// Sets (or removes, when blank) the alias for an item id.
    func setAlias(_ alias: String, for id: String) {
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard aliases[id] != nil else { return }
            aliases[id] = nil
        } else {
            guard aliases[id] != trimmed else { return }
            aliases[id] = trimmed
        }
        UserDefaults.standard.set(aliases, forKey: Self.storageKey)
        debounce?.cancel()
        let work = DispatchWorkItem {
            NotificationCenter.default.post(name: Self.aliasesDidUpdate, object: nil)
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
