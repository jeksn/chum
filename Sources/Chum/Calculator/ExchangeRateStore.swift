import Foundation
import ChumCore

/// Exchange rates for the launcher's currency conversions, from frankfurter.dev
/// (ECB daily reference rates, no API key). Fetched lazily — only when a
/// currency query is parsed — at most once per day, cached to disk, and still
/// usable offline from the cached table.
final class ExchangeRateStore {
    static let shared = ExchangeRateStore()

    private struct CachedRates: Codable {
        let base: String
        let date: String?
        let rates: [String: Double]
    }

    private var cache: CachedRates?
    private var cacheLoaded = false
    private var refreshing = false
    private var retryAfter = Date.distantPast
    private let stateLock = NSLock()
    private let fileURL: URL?

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Chum", isDirectory: true)
        fileURL = directory?.appendingPathComponent("rates.json")
    }

    /// The rates table for `Calculator.parse`, called on the main thread per
    /// keystroke — reads only an in-memory snapshot after the first access
    /// and kicks off a background refresh at most once per day.
    func currentRates() -> Calculator.RatesTable? {
        let cached = loadCached()
        if let cached {
            if !isFresh(cached) { startRefresh() }
        } else {
            // First run: without this, no fetch ever starts and currency
            // queries parse against no table until something else refreshes.
            startRefresh()
        }
        guard let cached else { return nil }
        return (base: cached.base, date: cached.date, rates: cached.rates)
    }

    private func loadCached() -> CachedRates? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if cacheLoaded { return usable(cache) }
        cacheLoaded = true
        cache = readFromDisk()
        return usable(cache)
    }

    /// A cached table is usable for the current base-currency setting only.
    private func usable(_ rates: CachedRates?) -> CachedRates? {
        guard let rates, rates.base.caseInsensitiveCompare(AppSettings.baseCurrency) == .orderedSame else { return nil }
        return rates
    }

    /// ECB publishes on target days; treat anything fetched "today" as fresh.
    private func isFresh(_ rates: CachedRates) -> Bool {
        guard let date = rates.date else { return false }
        return date == Self.todayString()
    }

    private func startRefresh() {
        stateLock.lock()
        guard !refreshing, Date() >= retryAfter else {
            stateLock.unlock()
            return
        }
        refreshing = true
        stateLock.unlock()

        let base = AppSettings.baseCurrency
        Task {
            let fetched = await Self.fetch(base: base)
            // Hop out of the async context before locking — NSLock is not
            // async-safe; the update region is tiny.
            await MainActor.run {
                self.finishRefresh(fetched)
            }
        }
    }

    private func finishRefresh(_ fetched: CachedRates?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        refreshing = false
        retryAfter = Date().addingTimeInterval(600)
        if let fetched {
            cache = fetched
            cacheLoaded = true
            writeToDisk(fetched)
        }
    }

    private static func fetch(base: String) async -> CachedRates? {
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(base)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ratesJSON = json["rates"] as? [String: Double] else { return nil }
        return CachedRates(
            base: (json["base"] as? String)?.uppercased() ?? base.uppercased(),
            date: json["date"] as? String,
            rates: ratesJSON
        )
    }

    private func readFromDisk() -> CachedRates? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedRates.self, from: data)
    }

    private func writeToDisk(_ rates: CachedRates) {
        guard let fileURL,
              let directory = fileURL.deletingLastPathComponent() as URL? else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(rates) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
