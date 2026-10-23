import Foundation
import ChumCore

enum URLDispatcher {
    static func handle(_ url: URL) {
        guard let action = ChumURL.parse(url) else { return }
        Task { @MainActor in
            switch action {
            case .apply(let name):
                guard let command = CommandStore.shared.command(named: name) else {
                    HUD.show("No command named \"\(name)\"")
                    return
                }
                CommandApplier.shared.apply(command)
            case .launcher:
                LauncherController.shared.show()
            case .ephemeral(let command):
                CommandApplier.shared.apply(command)
            }
        }
    }
}
