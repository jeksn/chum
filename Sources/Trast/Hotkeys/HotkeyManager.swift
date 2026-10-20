import TrastCore
import Foundation
import KeyboardShortcuts

final class HotkeyManager {
    static let shared = HotkeyManager()

    static let restore = KeyboardShortcuts.Name("restoreLastGeometry")
    static let openLauncher = KeyboardShortcuts.Name("openLauncher")
    static let nextWindow = KeyboardShortcuts.Name("nextWindow")
    static let openClipboard = KeyboardShortcuts.Name("openClipboard")
    static let openScratchpad = KeyboardShortcuts.Name("openScratchpad")
    static let openTextTransformer = KeyboardShortcuts.Name("openTextTransformer")
    static let openAIChat = KeyboardShortcuts.Name("openAIChat")
    static let openColorPicker = KeyboardShortcuts.Name("openColorPicker")

    private var registeredCommandIDs = Set<UUID>()
    private var registeredAppShortcutIDs = Set<UUID>()
    private var fixedNamesRegistered = false

    func registerAll(for store: CommandStore) {
        for command in store.commands {
            register(command)
        }

        guard !fixedNamesRegistered else { return }
        fixedNamesRegistered = true
        KeyboardShortcuts.onKeyUp(for: Self.restore) {
            CommandApplier.shared.restore()
        }
        KeyboardShortcuts.onKeyUp(for: Self.openLauncher) {
            LauncherController.shared.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: Self.nextWindow) {
            WindowCycler.cycleNext()
        }
        KeyboardShortcuts.onKeyUp(for: Self.openClipboard) {
            LauncherController.shared.showClipboard()
        }
        KeyboardShortcuts.onKeyUp(for: Self.openScratchpad) {
            LauncherController.shared.showScratchpad()
        }
        KeyboardShortcuts.onKeyUp(for: Self.openTextTransformer) {
            LauncherController.shared.showTextTransformer()
        }
        KeyboardShortcuts.onKeyUp(for: Self.openAIChat) {
            LauncherController.shared.showAIChat()
        }
        KeyboardShortcuts.onKeyUp(for: Self.openColorPicker) {
            LauncherController.shared.showColorPicker()
        }
        for action in WindowAction.all {
            register(action)
        }
    }

    func registerAllAppJumps(for store: AppShortcutStore) {
        for shortcut in store.shortcuts {
            register(shortcut)
        }
    }

    func register(_ shortcut: AppShortcut) {
        guard !registeredAppShortcutIDs.contains(shortcut.id) else { return }
        registeredAppShortcutIDs.insert(shortcut.id)

        let id = shortcut.id
        KeyboardShortcuts.onKeyUp(for: Self.appJumpName(for: id)) {
            Task { @MainActor in
                AppShortcutStore.shared.activate(id)
            }
        }
    }

    func register(_ command: WindowCommand) {
        guard !registeredCommandIDs.contains(command.id) else { return }
        registeredCommandIDs.insert(command.id)

        let id = command.id
        KeyboardShortcuts.onKeyUp(for: Self.name(for: id)) {
            guard let command = CommandStore.shared.command(withID: id) else { return }
            CommandApplier.shared.apply(command)
        }
    }

    private func register(_ action: WindowAction) {
        KeyboardShortcuts.onKeyUp(for: Self.actionName(action.id)) {
            CommandApplier.shared.apply(action.command)
        }
    }

    static func name(for id: UUID) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("command.\(id.uuidString)")
    }

    static func actionName(_ actionID: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("action.\(actionID)")
    }

    static func appJumpName(for id: UUID) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("appjump.\(id.uuidString)")
    }
}
