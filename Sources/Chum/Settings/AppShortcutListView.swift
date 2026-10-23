import KeyboardShortcuts
import SwiftUI
import ChumCore

struct AppShortcutListView: View {
    @EnvironmentObject private var store: AppShortcutStore
    @State private var selectionID: UUID?

    var body: some View {
        listBody
            .onAppear { applyPendingShortcut() }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                applyPendingShortcut()
            }
    }

    private func applyPendingShortcut() {
        if let id = SettingsWindow.pendingShortcutID {
            selectionID = id
            SettingsWindow.pendingShortcutID = nil
        }
    }

    private var listBody: some View {
        HSplitView {
            List(selection: $selectionID) {
                let apps = store.shortcuts.filter { $0.kind == .app }
                let urls = store.shortcuts.filter { $0.kind == .url }
                let folders = store.shortcuts.filter { $0.kind == .folder }

                if !apps.isEmpty {
                    Section("Apps") {
                        ForEach(apps) { shortcut in
                            row(for: shortcut)
                        }
                    }
                }
                if !urls.isEmpty {
                    Section("URLs") {
                        ForEach(urls) { shortcut in
                            row(for: shortcut)
                        }
                    }
                }
                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(folders) { shortcut in
                            row(for: shortcut)
                        }
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
                    AppShortcutEditorView(shortcut: binding) {
                        store.remove(binding.wrappedValue)
                        self.selectionID = nil
                    }
                } else {
                    Text("Select a shortcut")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let shortcut = store.add(AppShortcut())
                        selectionID = shortcut.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add shortcut")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        duplicateSelection()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(selectionID == nil)
                    .help("Duplicate shortcut")
                }
            }
        }
    }

    private func row(for shortcut: AppShortcut) -> some View {
        HStack {
            Image(systemName: icon(for: shortcut))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name.isEmpty ? "Untitled" : shortcut.name)
                    .lineLimit(1)
                if let subtitle = subtitle(for: shortcut) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if shortcut.showInMenuBar {
                Image(systemName: "menubar.dock.rectangle")
                    .foregroundStyle(.secondary)
                    .help("Shown in menu bar")
            }
            if let shortcut = KeyboardShortcuts.getShortcut(for: HotkeyManager.appJumpName(for: shortcut.id)) {
                Text(shortcut.hyperDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for shortcut: AppShortcut) -> String {
        switch shortcut.kind {
        case .app: return "arrow.right.square"
        case .url: return "link"
        case .folder: return "folder"
        }
    }

    private func subtitle(for shortcut: AppShortcut) -> String? {
        switch shortcut.kind {
        case .app:
            return shortcut.bundleIdentifier
        case .url:
            return shortcut.urlString
        case .folder:
            return shortcut.folderURL?.path
        }
    }

    private func duplicateSelection() {
        guard let selectionID, let shortcut = store.appShortcut(withID: selectionID) else { return }
        self.selectionID = store.duplicate(shortcut).id
    }
}
