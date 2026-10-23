import AppKit
import Foundation
import KeyboardShortcuts
import SwiftUI
import ChumCore

final class AppShortcutStore: ObservableObject {
    private struct StoredAppShortcuts: Codable {
        var version: Int
        var shortcuts: [AppShortcut]
    }

    static let shared = AppShortcutStore()

    @Published private(set) var shortcuts: [AppShortcut]

    private init() {
        if let loaded = Self.load() {
            shortcuts = loaded
        } else {
            shortcuts = []
            Self.save(shortcuts)
        }
    }

    var validShortcuts: [AppShortcut] {
        shortcuts.filter(\.isValid)
    }

    var pinnedShortcuts: [AppShortcut] {
        shortcuts.filter { $0.isValid && $0.showInMenuBar }
    }

    func appShortcut(withID id: UUID) -> AppShortcut? {
        shortcuts.first { $0.id == id }
    }

    @discardableResult
    func add(_ shortcut: AppShortcut) -> AppShortcut {
        var newShortcut = shortcut
        newShortcut.id = UUID()
        newShortcut.showInMenuBar = true
        shortcuts.append(newShortcut)
        save()
        HotkeyManager.shared.register(newShortcut)
        return newShortcut
    }

    func update(_ shortcut: AppShortcut) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[index] = shortcut
        save()
    }

    @discardableResult
    func duplicate(_ shortcut: AppShortcut) -> AppShortcut {
        var copy = shortcut
        copy.id = UUID()
        copy.name = uniqueName(basedOn: shortcut.name)
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts.insert(copy, at: index + 1)
        } else {
            shortcuts.append(copy)
        }
        save()
        HotkeyManager.shared.register(copy)
        return copy
    }

    func remove(_ shortcut: AppShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        KeyboardShortcuts.setShortcut(nil, for: HotkeyManager.appJumpName(for: shortcut.id))
        save()
    }

    func replace(with newShortcuts: [AppShortcut]) {
        for shortcut in shortcuts {
            KeyboardShortcuts.setShortcut(nil, for: HotkeyManager.appJumpName(for: shortcut.id))
        }
        shortcuts = newShortcuts
        save()
        for shortcut in shortcuts {
            HotkeyManager.shared.register(shortcut)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        shortcuts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func binding(for id: UUID) -> Binding<AppShortcut>? {
        guard shortcuts.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.appShortcut(withID: id) ?? AppShortcut() },
            set: { self.update($0) }
        )
    }

    func activate(_ id: UUID) {
        guard let shortcut = appShortcut(withID: id) else { return }
        guard shortcut.isValid else {
            Task { @MainActor in HUD.show("Shortcut is not valid") }
            return
        }

        switch shortcut.kind {
        case .url:
            guard let url = shortcut.url else {
                Task { @MainActor in HUD.show("Invalid URL") }
                return
            }
            let ok = NSWorkspace.shared.open(url)
            if !ok {
                Task { @MainActor in HUD.show("Could not open URL") }
            }
            return

        case .folder:
            guard let url = shortcut.folderURL else {
                Task { @MainActor in HUD.show("No folder selected") }
                return
            }
            let ok = NSWorkspace.shared.open(url)
            if !ok {
                Task { @MainActor in HUD.show("Could not open folder") }
            }
            return

        case .app:
            let url: URL?
            if let bundleID = shortcut.bundleIdentifier, !bundleID.isEmpty,
               let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                url = resolved
            } else if let bundleURL = shortcut.bundleURL {
                url = bundleURL
            } else {
                url = nil
            }

            guard let appURL = url else {
                Task { @MainActor in HUD.show("App not found") }
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.hides = false

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { runningApp, error in
                if let error {
                    Task { @MainActor in HUD.show(error.localizedDescription) }
                    return
                }
                runningApp?.activate(options: [.activateAllWindows])
            }
        }
    }

    private func save() {
        Self.save(shortcuts)
    }

    private func uniqueName(basedOn name: String) -> String {
        var candidate = "\(name) copy"
        var counter = 2
        while shortcuts.contains(where: { $0.name == candidate }) {
            candidate = "\(name) copy \(counter)"
            counter += 1
        }
        return candidate
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chum", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("appShortcuts.json")
    }

    private static func load() -> [AppShortcut]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredAppShortcuts.self, from: data) else { return nil }
        return stored.shortcuts
    }

    private static func save(_ shortcuts: [AppShortcut]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(StoredAppShortcuts(version: 1, shortcuts: shortcuts)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
