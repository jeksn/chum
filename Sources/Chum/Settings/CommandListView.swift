import SwiftUI
import KeyboardShortcuts
import ChumCore

struct CommandListView: View {
    @EnvironmentObject private var store: CommandStore
    @State private var selectionID: UUID?

    var body: some View {
        HSplitView {
            List(selection: $selectionID) {
                Section("Custom") {
                    ForEach(store.customCommands) { command in
                        row(for: command)
                    }
                    .onMove { store.moveCustom(from: $0, to: $1) }
                }
                Section {
                    ForEach(store.defaultCommands) { command in
                        row(for: command)
                    }
                } header: {
                    HStack {
                        Text("Defaults")
                        Spacer()
                        Button("Restore Defaults") {
                            store.restoreDefaults()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
            .listStyle(.sidebar)
            // Cancel the sidebar list's top content inset so the first
            // section header doesn't sit far below the toolbar.
            .padding(.top, -10)
            .frame(width: 260)

            Group {
                if let selectionID, let binding = store.binding(for: selectionID) {
                    CommandEditorView(command: binding) {
                        store.remove(binding.wrappedValue)
                        self.selectionID = nil
                    }
                } else {
                    Text("Select a command")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addCommand()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add command")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        duplicateSelection()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(selectionID == nil)
                    .help("Duplicate command")
                }
            }
        }
    }

    private func row(for command: WindowCommand) -> some View {
        HStack {
            Text(command.name.isEmpty ? "Untitled" : command.name)
                .lineLimit(1)
            Spacer()
            if command.showInMenuBar {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundStyle(.secondary)
                    .help("Shown in menu bar")
            }
            if let shortcut = KeyboardShortcuts.getShortcut(for: HotkeyManager.name(for: command.id)) {
                Text(shortcut.hyperDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addCommand() {
        var counter = store.customCommands.count + 1
        var name = "New Command"
        while store.commands.contains(where: { $0.name == name }) {
            counter += 1
            name = "New Command \(counter)"
        }
        let command = WindowCommand(name: name, width: .percent(50), height: .percent(50), anchor: .center)
        store.add(command)
        selectionID = command.id
    }

    private func duplicateSelection() {
        guard let selectionID, let command = store.command(withID: selectionID) else { return }
        self.selectionID = store.duplicate(command).id
    }
}
