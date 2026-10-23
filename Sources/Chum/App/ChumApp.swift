import ChumCore
import SwiftUI
import KeyboardShortcuts

@main
struct ChumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CommandStore.shared
    @StateObject private var appShortcutStore = AppShortcutStore.shared
    @StateObject private var snippetStore = SnippetStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(appShortcutStore)
        } label: {
            StatusBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Window("", id: "settings") {
            SettingsView()
                .environmentObject(store)
                .environmentObject(appShortcutStore)
                .environmentObject(snippetStore)
        }
        .windowResizability(.contentSize)
    }
}

/// Shared open-settings sequence used by the menu bar, the launcher, and the
/// notification observer.
enum SettingsWindow {
    /// A requested landing spot for the next Settings open, consumed by
    /// SettingsView / AppShortcutListView (the launcher's Add as Shortcut
    /// hands off here).
    static var pendingSection: SettingsSection?
    static var pendingShortcutID: UUID?

    static func open(_ openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .first { !($0 is NSPanel) }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

/// The menu-bar label is alive for the entire app lifetime, unlike the
/// `.menu`-style MenuBarExtra content, which SwiftUI only instantiates while
/// the menu is open — so this is the only reliable observer for
/// open-settings requests posted while the menu is closed (e.g. from the
/// launcher).
private struct StatusBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: StatusBarIcon.image)
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                SettingsWindow.open(openWindow)
            }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var store: CommandStore
    @EnvironmentObject private var appShortcutStore: AppShortcutStore
    @Environment(\.openWindow) private var openWindow
    @State private var isTrusted = Accessibility.isTrusted

    var body: some View {
        Group {
            if !isTrusted {
                Button("Enable Accessibility Permission…") {
                    Accessibility.openSystemSettings()
                }
                Divider()
            }

            if store.pinnedCommands.isEmpty {
                Button("No pinned commands — choose in Settings…") {
                    openSettingsWindow()
                }
            }
            ForEach(store.pinnedCommands) { command in
                Button(command.name.isEmpty ? "Untitled" : command.name) {
                    CommandApplier.shared.apply(command)
                }
                .keyboardShortcut(for: command)
            }

            if !appShortcutStore.pinnedShortcuts.isEmpty {
                Divider()
                Menu("Shortcuts") {
                    ForEach(appShortcutStore.pinnedShortcuts) { shortcut in
                        Button(shortcut.name.isEmpty ? "Untitled" : shortcut.name) {
                            AppShortcutStore.shared.activate(shortcut.id)
                        }
                        .keyboardShortcut(for: shortcut)
                    }
                }
            }

            Divider()
            Button("Open Launcher") {
                LauncherController.shared.show()
            }
            Button("Settings") {
                openSettingsWindow()
            }
            Button("Check for Updates") {
                UpdateChecker.checkForUpdates()
            }
            Button("Quit Chum") {
                NSApp.terminate(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            openSettingsWindow()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            let updated = Accessibility.isTrusted
            if updated != isTrusted { isTrusted = updated }
        }
    }

    private func openSettingsWindow() {
        SettingsWindow.open(openWindow)
    }
}

private extension View {
    func keyboardShortcut(for command: WindowCommand) -> some View {
        if let shortcut = KeyboardShortcuts.getShortcut(for: HotkeyManager.name(for: command.id)),
           let ks = shortcut.swiftUIShortcut {
            return AnyView(self.keyboardShortcut(ks))
        }
        return AnyView(self)
    }

    func keyboardShortcut(for shortcut: AppShortcut) -> some View {
        if let hotkey = KeyboardShortcuts.getShortcut(for: HotkeyManager.appJumpName(for: shortcut.id)),
           let ks = hotkey.swiftUIShortcut {
            return AnyView(self.keyboardShortcut(ks))
        }
        return AnyView(self)
    }
}
