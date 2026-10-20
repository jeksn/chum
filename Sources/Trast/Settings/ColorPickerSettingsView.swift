import SwiftUI
import TrastCore

struct ColorPickerSettingsView: View {
    @ObservedObject private var colorStore = ColorStore.shared
    @State private var confirmDeleteAll = false

    var body: some View {
        Form {
            Section {
                HotkeyRecorderView("Open Color Picker:", name: HotkeyManager.openColorPicker)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Opens the Launcher on the Color Picker tab; press again to close. \"Pick Color from Screen\" runs the system eyedropper and saves the color to the list.")
            }

            Section {
                if confirmDeleteAll {
                    Text("\(colorStore.colors.count) color(s) will be deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(role: .destructive) {
                            colorStore.clearAll()
                            LauncherController.shared.refreshItems()
                            confirmDeleteAll = false
                        } label: {
                            Text("Delete All Colors")
                        }
                        Button {
                            confirmDeleteAll = false
                        } label: {
                            Text("Cancel")
                        }
                    }
                } else {
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Text("Delete All Colors")
                    }
                    .disabled(colorStore.colors.isEmpty)
                }
            } header: {
                Text("Saved Colors")
            } footer: {
                Text("Saved colors persist in Application Support and survive relaunches. Return on a color copies its hex; the row's context menu copies rgb/hsl and removes entries.")
            }
        }
        .formStyle(.grouped)
    }
}
