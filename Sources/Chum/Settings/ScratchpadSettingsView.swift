import SwiftUI
import ChumCore

struct ScratchpadSettingsView: View {
    @ObservedObject private var notesStore = NotesStore.shared
    @State private var confirmDeleteAll = false

    var body: some View {
        Form {
            Section {
                HotkeyRecorderView("Open Scratchpad:", name: HotkeyManager.openScratchpad)
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Opens the Launcher on the Scratchpad tab; press again to close.")
            }

            Section {
                if confirmDeleteAll {
                    Text("\(notesStore.notes.count) note(s) will be deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(role: .destructive) {
                            notesStore.deleteAll()
                            confirmDeleteAll = false
                        } label: {
                            Text("Delete All Notes")
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
                        Text("Delete All Notes")
                    }
                    .disabled(notesStore.notes.isEmpty)
                }
            } header: {
                Text("Notes")
            } footer: {
                Text("Notes live in the Launcher's Scratchpad: ⌘N creates a new note, ⌘P lists them. They persist in Application Support and survive relaunches; the list shows only a one-line excerpt of each note.")
            }
        }
        .formStyle(.grouped)
    }
}
