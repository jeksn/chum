import Foundation

final class UsageTracker {
    static let shared = UsageTracker()

    private struct Log: Codable {
        var entries: [String: Date]
    }

    private static let key = "launcherUsageLog"
    private var entries: [String: Date]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let log = try? JSONDecoder().decode(Log.self, from: data) {
            entries = log.entries
        } else {
            entries = [:]
        }
    }

    func record(_ id: String) {
        entries[id] = Date()
        save()
    }

    func timestamp(for id: String) -> Date? {
        entries[id]
    }

    func sortedByRecent(_ ids: [String]) -> [String] {
        ids.sorted { a, b in
            let ta = entries[a] ?? .distantPast
            let tb = entries[b] ?? .distantPast
            return ta > tb
        }
    }

    private func save() {
        let log = Log(entries: entries)
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
