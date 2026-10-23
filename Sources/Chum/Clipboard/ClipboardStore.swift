import Foundation
import ChumCore

final class ClipboardStore: ObservableObject {
    private struct StoredClipboard: Codable {
        var version: Int
        var items: [ClipboardItem]
    }

    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem]

    private init() {
        if let loaded = Self.load() {
            items = loaded
        } else {
            items = []
            Self.save(items)
        }
    }

    var maxItems: Int {
        let value = UserDefaults.standard.integer(forKey: AppSettings.clipboardHistorySizeKey)
        return value > 0 ? value : 100
    }

    var autoClearSeconds: TimeInterval {
        let value = UserDefaults.standard.double(forKey: AppSettings.clipboardAutoClearKey)
        return value > 0 ? value : 0
    }

    func add(_ item: ClipboardItem) {
        if isDuplicate(item) { return }
        items.insert(item, at: 0)
        enforceMaxItems()
        purgeExpired()
        save()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    func clearAll() {
        items = items.filter { $0.pinned }
        save()
    }

    func clearExpired() {
        purgeExpired()
        save()
    }

    private func isDuplicate(_ item: ClipboardItem) -> Bool {
        guard let first = items.first else { return false }
        if first.kind != item.kind { return false }
        switch item.kind {
        case .text:
            return first.textContent == item.textContent
        case .image:
            return first.imageData == item.imageData
        case .fileURL:
            return first.fileURLString == item.fileURLString
        }
    }

    private func enforceMaxItems() {
        let nonPinned = items.filter { !$0.pinned }
        let pinned = items.filter { $0.pinned }
        let maxNonPinned = max(maxItems - pinned.count, 0)
        if nonPinned.count > maxNonPinned {
            let keptNonPinned = Array(nonPinned.prefix(maxNonPinned))
            items = keptNonPinned + pinned
        }
    }

    private func purgeExpired() {
        let seconds = autoClearSeconds
        guard seconds > 0 else { return }
        let cutoff = Date().addingTimeInterval(-seconds)
        items.removeAll { !$0.pinned && $0.timestamp < cutoff }
    }

    private func save() {
        Self.save(items)
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chum", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("clipboard.json")
    }

    private static func load() -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredClipboard.self, from: data) else { return nil }
        return stored.items
    }

    private static func save(_ items: [ClipboardItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(StoredClipboard(version: 1, items: items)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
