import AppKit
import ChumCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigMigration.migrateIfNeeded()
        AppScanner.refresh()
        AppScanner.startWatching()
        _ = ExchangeRateStore.shared.currentRates()
        ClipboardMonitor.shared.start()
        SnippetExpander.shared.start()
        HyperkeyEngine.shared.start()
        HotkeyManager.shared.registerAll(for: CommandStore.shared)
        HotkeyManager.shared.registerAllAppJumps(for: AppShortcutStore.shared)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(0x4755524C),
            andEventID: AEEventID(0x4755524C)
        )

        if AppSettings.autoCheckUpdates {
            UpdateChecker.checkForUpdatesOnLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reverts the Caps Lock driver remap so it doesn't linger until reboot.
        HyperkeyEngine.shared.stop()
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(0x2D2D2D2D))?.stringValue,
            let url = URL(string: urlString)
        else { return }
        URLDispatcher.handle(url)
    }
}
