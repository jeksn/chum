import Foundation
import SwiftUI
import ChumCore
import KeyboardShortcuts

final class CommandStore: ObservableObject {
    private struct StoredCommands: Codable {
        var version: Int
        var commands: [WindowCommand]
    }

    static let shared = CommandStore()

    @Published private(set) var commands: [WindowCommand]

    private init() {
        if let loaded = Self.load() {
            commands = loaded
        } else {
            commands = WindowCommand.seeds
            Self.save(commands)
        }
    }

    var defaultCommands: [WindowCommand] {
        commands.filter(\.isDefault)
    }

    var customCommands: [WindowCommand] {
        commands.filter { !$0.isDefault }
    }

    var pinnedCommands: [WindowCommand] {
        commands.filter(\.showInMenuBar)
    }

    func command(withID id: UUID) -> WindowCommand? {
        commands.first { $0.id == id }
    }

    func command(named name: String) -> WindowCommand? {
        commands.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func add(_ command: WindowCommand) {
        var newCommand = command
        newCommand.isDefault = false
        newCommand.showInMenuBar = true
        commands.append(newCommand)
        save()
        HotkeyManager.shared.register(newCommand)
    }

    func update(_ command: WindowCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        save()
    }

    @discardableResult
    func duplicate(_ command: WindowCommand) -> WindowCommand {
        var copy = command
        copy.id = UUID()
        copy.name = uniqueName(basedOn: command.name)
        copy.isDefault = false
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            if command.isDefault, let customStart = commands.firstIndex(where: { !$0.isDefault }) {
                commands.insert(copy, at: customStart)
            } else {
                commands.insert(copy, at: index + 1)
            }
        } else {
            commands.append(copy)
        }
        save()
        HotkeyManager.shared.register(copy)
        return copy
    }

    func remove(_ command: WindowCommand) {
        guard !command.isDefault else { return }
        commands.removeAll { $0.id == command.id }
        KeyboardShortcuts.setShortcut(nil, for: HotkeyManager.name(for: command.id))
        save()
    }

    func restoreDefaults() {
        let existingNames = Set(commands.map(\.name))
        let missing = WindowCommand.seeds.filter { !existingNames.contains($0.name) }
        guard !missing.isEmpty else { return }
        let insertIndex = commands.firstIndex(where: { !$0.isDefault }) ?? commands.count
        commands.insert(contentsOf: missing, at: insertIndex)
        save()
        missing.forEach { HotkeyManager.shared.register($0) }
    }

    func replace(with newCommands: [WindowCommand]) {
        for command in commands {
            KeyboardShortcuts.setShortcut(nil, for: HotkeyManager.name(for: command.id))
        }
        commands = newCommands
        save()
        for command in commands {
            HotkeyManager.shared.register(command)
        }
    }

    func moveCustom(from source: IndexSet, to destination: Int) {
        guard let customStart = commands.firstIndex(where: { !$0.isDefault }) else { return }
        let fullSource = IndexSet(source.map { $0 + customStart })
        commands.move(fromOffsets: fullSource, toOffset: destination + customStart)
        save()
    }

    func binding(for id: UUID) -> Binding<WindowCommand>? {
        guard commands.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.command(withID: id) ?? WindowCommand() },
            set: { self.update($0) }
        )
    }

    private func save() {
        Self.save(commands)
    }

    private func uniqueName(basedOn name: String) -> String {
        var candidate = "\(name) copy"
        var counter = 2
        while commands.contains(where: { $0.name == candidate }) {
            candidate = "\(name) copy \(counter)"
            counter += 1
        }
        return candidate
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chum", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("commands.json")
    }

    private static func load() -> [WindowCommand]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        if let stored = try? JSONDecoder().decode(StoredCommands.self, from: data) {
            if stored.version >= 3 {
                return stored.commands
            }
            let (commands, droppedActionIDs) = migrateActionCommands(stored.commands)
            remapActionHotkeys(droppedActionIDs)
            save(commands)
            return commands
        }
        if let legacy = try? JSONDecoder().decode([WindowCommand].self, from: data) {
            let result = WindowCommand.migratingLegacyCommands(legacy)
            remapActionHotkeys(result.droppedActionIDs)
            save(result.commands)
            return result.commands
        }
        return nil
    }

    private static func migrateActionCommands(_ commands: [WindowCommand]) -> ([WindowCommand], [String: UUID]) {
        var droppedActionIDs = [String: UUID]()
        var kept: [WindowCommand] = []
        for command in commands {
            if let action = WindowAction.all.first(where: { $0.name == command.name }) {
                droppedActionIDs[action.id] = command.id
            } else {
                kept.append(command)
            }
        }
        return (kept, droppedActionIDs)
    }

    private static func remapActionHotkeys(_ droppedActionIDs: [String: UUID]) {
        for (actionID, oldCommandID) in droppedActionIDs {
            let oldName = HotkeyManager.name(for: oldCommandID)
            guard let shortcut = KeyboardShortcuts.getShortcut(for: oldName) else { continue }
            let newName = HotkeyManager.actionName(actionID)
            KeyboardShortcuts.setShortcut(shortcut, for: newName)
            KeyboardShortcuts.setShortcut(nil, for: oldName)
        }
    }

    private static func save(_ commands: [WindowCommand]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(StoredCommands(version: 3, commands: commands)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
