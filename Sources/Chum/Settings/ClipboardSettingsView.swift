import SwiftUI
import ChumCore

struct ClipboardSettingsView: View {
    @AppStorage(AppSettings.clipboardEnabledKey) private var monitorEnabled: Bool = true
    @AppStorage(AppSettings.clipboardHistorySizeKey) private var historySize: Double = 100
    @AppStorage(AppSettings.clipboardAutoClearKey) private var autoClearSeconds: Double = 0

    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Enable clipboard monitoring", isOn: $monitorEnabled)
                    .onChange(of: monitorEnabled) { enabled in
                        if enabled {
                            ClipboardMonitor.shared.start()
                        } else {
                            ClipboardMonitor.shared.stop()
                        }
                    }
            }
            Section {
                HStack {
                    Text("History size")
                    Spacer()
                    TextField("", value: $historySize, format: .number)
                        .frame(width: 76)
                        .multilineTextAlignment(.trailing)
                    Text("items")
                        .foregroundStyle(.secondary)
                }
                Picker("Auto-clear", selection: $autoClearSeconds) {
                    Text("Never").tag(0.0)
                    Text("After 1 minute").tag(60.0)
                    Text("After 5 minutes").tag(300.0)
                    Text("After 30 minutes").tag(1800.0)
                    Text("After 1 hour").tag(3600.0)
                }
            } header: {
                Text("Retention")
            } footer: {
                Text("Pinned items are never auto-cleared. The history is stored at ~/Library/Application Support/Chum/clipboard.json.")
            }
            Section {
                Button(role: .destructive) {
                    ClipboardStore.shared.clearAll()
                } label: {
                    Text("Clear History")
                }
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
    }
}
