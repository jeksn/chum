import AppKit
import KeyboardShortcuts
import SwiftUI
import ChumCore

struct AppShortcutEditorView: View {
    @Binding var shortcut: AppShortcut
    var onDelete: (() -> Void)?

    @State private var showingChooser = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Shortcut") {
                TextField("Name", text: $shortcut.name)

                Picker("Kind", selection: $shortcut.kind) {
                    ForEach(AppShortcut.Kind.allCases, id: \.self) { kind in
                        Text(label(for: kind)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show in Menu Bar", isOn: $shortcut.showInMenuBar)
            }

            switch shortcut.kind {
            case .app:
                appSection
            case .url:
                urlSection
            case .folder:
                folderSection
            }

            Section("Hotkey") {
                HotkeyRecorderView("Hotkey:", name: HotkeyManager.appJumpName(for: shortcut.id))
            }

            Section {
                Button("Test Shortcut") {
                    AppShortcutStore.shared.activate(shortcut.id)
                }
                .disabled(!shortcut.isValid)
            } header: {
                Text("Test")
            } footer: {
                Text("Launches or opens the configured app, URL, or folder without closing this editor.")
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Shortcut…")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: shortcut.kind) { _ in
            clearFieldsForNewKind()
        }
        .sheet(isPresented: $showingChooser) {
            AppChooserView { item in
                chooseApp(item)
            }
        }
        .confirmationDialog(
            "Delete \"\(shortcut.name)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This shortcut and its hotkey will be removed. This cannot be undone.")
        }
    }

    private func label(for kind: AppShortcut.Kind) -> String {
        switch kind {
        case .app: return "App"
        case .url: return "URL / Link"
        case .folder: return "Folder / File"
        }
    }

    private func clearFieldsForNewKind() {
        if shortcut.name.isEmpty || shortcut.name == defaultNameFor(kind: shortcut.kind) {
            shortcut.name = ""
        }
    }

    private func defaultNameFor(kind: AppShortcut.Kind) -> String {
        switch kind {
        case .app: return ""
        case .url: return ""
        case .folder: return ""
        }
    }

    private var appSection: some View {
        Section("App") {
            HStack(spacing: 12) {
                appIcon
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.name.isEmpty ? "No app selected" : shortcut.name)
                        .lineLimit(1)
                    if let bundleID = shortcut.bundleIdentifier, !bundleID.isEmpty {
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Choose…") { showingChooser = true }
            }
        }
    }

    private var urlSection: some View {
        Section("URL") {
            TextField("URL", text: urlStringBinding)
                .textFieldStyle(.roundedBorder)
            if let url = shortcut.url {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if shortcut.urlString?.isEmpty == false {
                Text("Invalid URL")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var folderSection: some View {
        Section("Folder / File") {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.name.isEmpty ? "No folder selected" : shortcut.name)
                        .lineLimit(1)
                    if let path = shortcut.folderURL?.path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Choose…") { chooseFolder() }
            }
        }
    }

    private var urlStringBinding: Binding<String> {
        Binding(
            get: { shortcut.urlString ?? "" },
            set: { newValue in
                shortcut.urlString = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func chooseApp(_ item: AppChooserItem) {
        shortcut.name = item.name
        shortcut.bundleIdentifier = item.bundleIdentifier
        shortcut.bundleURL = item.bundleURL
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                shortcut.folderURL = url
                if shortcut.name.isEmpty {
                    shortcut.name = url.lastPathComponent
                }
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        let image: NSImage? = {
            if let bundleID = shortcut.bundleIdentifier, !bundleID.isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            } else if let bundleURL = shortcut.bundleURL {
                return NSWorkspace.shared.icon(forFile: bundleURL.path)
            }
            return nil
        }()

        if let nsImage = image {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
