import Foundation
import ChumCore

/// Persistent usage memory for launcher items and window commands: how many
/// times each id was used and when it was last used. Scores (decayed
/// frequency, see `UsageScore`) feed the launcher's empty-category ordering
/// and the search rank boost, and command applications from hotkeys, the menu
/// bar, and URLs are recorded here too — not just launcher activations.
final class UsageTracker {
    static let shared = UsageTracker()

    struct Entry: Codable {
        var count: Int
        var lastUsed: Date
    }

    private struct Log: Codable {
        var entries: [String: Entry]
    }

    /// Legacy format: bare last-used timestamps, one use implied.
    private struct LegacyLog: Codable {
        var entries: [String: Date]
    }

    private static let key = "launcherUsageLog"
    private let lock = NSLock()
    private var entries: [String: Entry]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            if let log = try? JSONDecoder().decode(Log.self, from: data) {
                entries = log.entries
            } else if let legacy = try? JSONDecoder().decode(LegacyLog.self, from: data) {
                entries = legacy.entries.mapValues { Entry(count: 1, lastUsed: $0) }
                if let data = try? JSONEncoder().encode(Log(entries: entries)) {
                    UserDefaults.standard.set(data, forKey: Self.key)
                }
            } else {
                entries = [:]
            }
        } else {
            entries = [:]
        }
    }

    /// Thread-safe; callers on the hotkey path should dispatch to a
    /// background queue so the UserDefaults write never adds latency to
    /// window application.
    func record(_ id: String) {
        lock.lock()
        let previous = entries[id]
        entries[id] = Entry(count: (previous?.count ?? 0) + 1, lastUsed: Date())
        let log = Log(entries: entries)
        lock.unlock()
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func count(for id: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return entries[id]?.count ?? 0
    }

    func timestamp(for id: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return entries[id]?.lastUsed
    }

    /// Decayed frequency score for the id (0 when never used).
    func score(for id: String, now: Date = Date()) -> Double {
        lock.lock(); defer { lock.unlock() }
        return scoreUnlocked(for: id, now: now)
    }

    /// Caller must hold `lock`.
    private func scoreUnlocked(for id: String, now: Date) -> Double {
        guard let entry = entries[id] else { return 0 }
        return UsageScore.score(count: entry.count, lastUsed: entry.lastUsed, now: now)
    }

    /// Bounded bonus added to the id's fuzzy match score during search.
    func rankBonus(for id: String, now: Date = Date()) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[id] else { return 0 }
        return UsageScore.rankBonus(count: entry.count, lastUsed: entry.lastUsed, now: now)
    }

    func sortedByRecent(_ ids: [String]) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return ids.sorted { a, b in
            let ta = entries[a]?.lastUsed ?? .distantPast
            let tb = entries[b]?.lastUsed ?? .distantPast
            return ta > tb
        }
    }

    /// Most-used-first: decayed frequency score, ties broken by recency.
    func sortedByScore(_ ids: [String], now: Date = Date()) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return ids.sorted { a, b in
            let sa = scoreUnlocked(for: a, now: now)
            let sb = scoreUnlocked(for: b, now: now)
            if sa != sb { return sa > sb }
            return (entries[a]?.lastUsed ?? .distantPast) > (entries[b]?.lastUsed ?? .distantPast)
        }
    }
}
