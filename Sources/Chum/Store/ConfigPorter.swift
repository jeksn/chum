import Foundation
import ChumCore

enum ConfigPorter {
    struct ExportBundle: Codable {
        var version: Int
        var commands: [WindowCommand]
        var appShortcuts: [AppShortcut]
    }

    static func exportData() -> Data? {
        let bundle = ExportBundle(
            version: 1,
            commands: CommandStore.shared.commands,
            appShortcuts: AppShortcutStore.shared.shortcuts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(bundle)
    }

    @discardableResult
    static func importData(_ data: Data) -> Bool {
        guard let bundle = try? JSONDecoder().decode(ExportBundle.self, from: data) else { return false }
        CommandStore.shared.replace(with: bundle.commands)
        AppShortcutStore.shared.replace(with: bundle.appShortcuts)
        return true
    }
}
