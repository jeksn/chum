import SwiftUI
import KeyboardShortcuts
import TrastCore

struct WindowSettingsView: View {
    @AppStorage(AppSettings.gapKey) private var gap: Double = 0
    @AppStorage(AppSettings.cycleHalvesKey) private var cycleHalves = false

    var body: some View {
        Form {
            Section("Hotkeys") {
                HotkeyRecorderView("Clipboard History:", name: HotkeyManager.openClipboard)
                HotkeyRecorderView("Restore Previous Size:", name: HotkeyManager.restore)
                HotkeyRecorderView("Next Window:", name: HotkeyManager.nextWindow)
            }

            Section {
                ForEach(WindowAction.all) { action in
                    HotkeyRecorderView("\(action.name):", name: HotkeyManager.actionName(action.id))
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("Parameterless actions — they keep the window's size and only change its position. Also available in the Launcher.")
            }

            Section {
                Picker("Gap", selection: $gap) {
                    Text("Small").tag(10.0)
                    Text("Medium").tag(20.0)
                    Text("Large").tag(40.0)
                    Text("Extra Large").tag(60.0)
                }
                .pickerStyle(.segmented)

                Toggle("Cycle half sizes", isOn: $cycleHalves)
            } header: {
                Text("Sizing")
            } footer: {
                Text("Spacing between windows and screen edges. With cycle on, pressing the same half command again steps its size through 1/2, 1/3 and 2/3; any other command resets the cycle.")
            }
        }
        .formStyle(.grouped)
    }
}
