import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import UniformTypeIdentifiers
import ChumCore
import AppKit
import CoreGraphics

struct GeneralSettingsView: View {
    @AppStorage(AppSettings.autoCheckUpdatesKey) private var autoCheckUpdates: Bool = true
    @AppStorage(AppSettings.snippetsEnabledKey) private var snippetsEnabled: Bool = false
    @AppStorage(AppSettings.hyperKeyEnabledKey) private var hyperKeyEnabled: Bool = false
    @AppStorage(AppSettings.hyperSymbolKey) private var hyperSymbol: Bool = true
    @AppStorage(AppSettings.launcherSlightTransparencyKey) private var slightTransparency: Bool = true
    @AppStorage(AppSettings.launcherClipboardTabKey) private var showClipboardTab: Bool = true
    @AppStorage(AppSettings.launcherSnippetsTabKey) private var showSnippetsTab: Bool = true
    @AppStorage(AppSettings.baseCurrencyKey) private var baseCurrency: String = "USD"
    @AppStorage(AppSettings.preferredUnitsKey) private var preferredUnits: String = "metric"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isTrusted = Accessibility.isTrusted
    @State private var inputMonitoringGranted = false
    @State private var importError = false

    var body: some View {
        Form {
            Section {
                HotkeyRecorderView("Launcher:", name: HotkeyManager.openLauncher)
                Toggle("Slight transparency", isOn: $slightTransparency)
                Toggle("Show Clipboard tab", isOn: $showClipboardTab)
                Toggle("Show Snippets tab", isOn: $showSnippetsTab)
            } header: {
                Text("Launcher")
            } footer: {
                Text("Press this shortcut anywhere to open the Launcher. It opens as a bare search bar; press ↓, Tab, or the list button for the tools/favorites/recent activity view. Slight transparency keeps a subtle translucency (85%); turn it off for a fully opaque panel. The Clipboard tab shows full clipboard history; the Snippets tab shows available text snippets.")
            }

            Section {
                Toggle("Enable snippet expansion", isOn: $snippetsEnabled)
                    .onChange(of: snippetsEnabled) { enabled in
                        if enabled {
                            SnippetExpander.shared.start()
                            inputMonitoringGranted = CGPreflightListenEventAccess()
                        } else {
                            SnippetExpander.shared.stop()
                        }
                    }
                if snippetsEnabled && !inputMonitoringGranted {
                    HStack {
                        Label(
                            "Input Monitoring permission required",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Color.orange)
                        Spacer()
                        Button("Open System Settings") {
                            Accessibility.openSystemSettings()
                        }
                    }
                }
            } header: {
                Text("Snippets")
            } footer: {
                Text("Type a snippet keyword anywhere to expand it. Requires Input Monitoring permission (prompted on first enable) and Accessibility for text injection.")
            }

            Section {
                Toggle("Enable hyper key (Caps Lock → ⌃⌥⇧⌘)", isOn: $hyperKeyEnabled)
                    .onChange(of: hyperKeyEnabled) { enabled in
                        if enabled {
                            HyperkeyEngine.shared.start()
                            isTrusted = Accessibility.isTrusted
                            inputMonitoringGranted = CGPreflightListenEventAccess()
                        } else {
                            HyperkeyEngine.shared.stop()
                        }
                    }
                if hyperKeyEnabled && !isTrusted {
                    HStack {
                        Label(
                            "Accessibility permission required",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Color.orange)
                        Spacer()
                        Button("Open System Settings") {
                            Accessibility.openSystemSettings()
                        }
                    }
                }
                if hyperKeyEnabled && !inputMonitoringGranted {
                    HStack {
                        Label(
                            "Input Monitoring permission required",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Color.orange)
                        Spacer()
                        Button("Open System Settings") {
                            Accessibility.openSystemSettings()
                        }
                    }
                }
                Toggle("Show as ✦ in shortcut labels", isOn: $hyperSymbol)
            } header: {
                Text("Hyper Key")
            } footer: {
                Text("Hold Caps Lock to send ⌃⌥⇧⌘ — a modifier combo no other app uses, ideal for Chum hotkeys. A lone Caps Lock tap does nothing. While enabled, Caps Lock is remapped at the driver level (to F18) so the lock state and LED stay off; this reverts when disabled and replaces any Caps Lock remap from System Settings. Requires Accessibility (Input Monitoring is no longer needed — detection lives in the event tap itself). Quit Hyperkey.app or other Caps Lock remappers first — two active remappers on the same key conflict.")
            }

            Section {
                Picker("Base currency", selection: $baseCurrency) {
                    ForEach(Calculator.supportedCurrencies, id: \.self) { code in
                        Text(code)
                    }
                }
                Picker("Preferred units", selection: $preferredUnits) {
                    Text("Metric").tag("metric")
                    Text("Imperial").tag("imperial")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Calculator")
            } footer: {
                Text("Type math (2^10*2), unit conversions (5 km to miles), or currency (10 usd to eur) in the Launcher and press Return to copy the result. Bare amounts convert to the base currency; bare units convert to the preferred system. Currency rates come from the ECB and are fetched once a day.")
            }

            Section {
                Button("Export Configuration…") { exportConfig() }
                Button("Import Configuration…") { importConfig() }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves or restores all commands and shortcuts to a JSON file. Hotkey bindings are not included — reassign them after importing on a new machine.")
            }

            Section("System") {
                LabeledContent("Version", value: UpdateChecker.currentVersion)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Check for updates on launch", isOn: $autoCheckUpdates)
                Button("Check for Updates…") {
                    UpdateChecker.checkForUpdates()
                }
                HStack {
                    Label(
                        isTrusted ? "Accessibility granted" : "Accessibility permission required",
                        systemImage: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isTrusted ? Color.green : Color.orange)
                    Spacer()
                    Button("Refresh") { isTrusted = Accessibility.isTrusted }
                    Button("Open System Settings") {
                        Accessibility.openSystemSettings()
                    }
                }
            }

            Section("URL Scheme") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("chum://apply?name=Left%20Half")
                    Text("chum://launcher")
                    Text("chum://command?position=center&relativeWidth=0.5&relativeHeight=0.5")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            isTrusted = Accessibility.isTrusted
            inputMonitoringGranted = CGPreflightListenEventAccess()
        }
        .alert("Import Failed", isPresented: $importError) {
            Button("OK") { }
        } message: {
            Text("The selected file could not be read as a Chum configuration file.")
        }
    }

    private func exportConfig() {
        guard let data = ConfigPorter.exportData() else { return }
        let panel = NSSavePanel()
        panel.title = "Export Chum Configuration"
        panel.nameFieldStringValue = "chum-config.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.title = "Import Chum Configuration"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard let data = try? Data(contentsOf: url) else {
                importError = true
                return
            }
            if !ConfigPorter.importData(data) {
                importError = true
            }
        }
    }
}
