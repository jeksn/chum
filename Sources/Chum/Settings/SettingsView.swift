import SwiftUI
import ChumCore

struct SettingsView: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        settingsBody
            .onAppear { applyPendingSection() }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                applyPendingSection()
            }
    }

    private func applyPendingSection() {
        if let section = SettingsWindow.pendingSection {
            selection = section
            SettingsWindow.pendingSection = nil
        }
    }

    private var settingsBody: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsView()
            case .window:
                WindowSettingsView()
            case .commands:
                CommandListView()
            case .shortcuts:
                AppShortcutListView()
            case .snippets:
                SnippetListView()
            case .clipboard:
                ClipboardSettingsView()
            case .colorPicker:
                ColorPickerSettingsView()
            case .textTransformer:
                TextTransformerSettingsView()
            case .aiChat:
                AIChatSettingsView()
            case .scratchpad:
                ScratchpadSettingsView()
            }
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case window
    case commands
    case shortcuts
    case snippets
    case clipboard
    case colorPicker
    case textTransformer
    case aiChat
    case scratchpad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .window: return "Window"
        case .commands: return "Commands"
        case .shortcuts: return "Shortcuts"
        case .snippets: return "Snippets"
        case .clipboard: return "Clipboard"
        case .colorPicker: return "Color Picker"
        case .textTransformer: return "Text Transformer"
        case .aiChat: return "AI Chat"
        case .scratchpad: return "Scratchpad"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .window: return "macwindow"
        case .commands: return "rectangle.split.2x2"
        case .shortcuts: return "arrow.right.square"
        case .snippets: return "text.append"
        case .clipboard: return "clipboard"
        case .colorPicker: return "eyedropper"
        case .textTransformer: return "textformat"
        case .aiChat: return "sparkles"
        case .scratchpad: return "square.and.pencil"
        }
    }
}
