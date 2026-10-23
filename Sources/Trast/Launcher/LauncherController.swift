import TrastCore
import AppKit
import KeyboardShortcuts
import SwiftUI
import Combine

extension Notification.Name {
    static let openSettings = Notification.Name("TrastOpenSettings")
}

final class LauncherController: NSObject, NSWindowDelegate {
    static let shared = LauncherController()

    private var panel: LauncherPanel?
    private let viewModel = LauncherViewModel()
    private var target: WindowRef?
    private var keyMonitor: Any?
    private var resizeCancellable: AnyCancellable?
    private var appsUpdateObserver: NSObjectProtocol?
    private var lastTargetFrame: NSRect?
    private var resizeScheduled = false
    private var lastLayoutSignature: LayoutSignature?

    /// Everything that determines the panel's content height. Selection and
    /// hover changes don't affect it, so they don't need a layout pass.
    private struct LayoutSignature: Equatable {
        let category: LauncherViewModel.Category
        let sectionTitles: [String]
        let rowCount: Int
        // Tool-internal state swaps views of very different heights under
        // the same category (transformer capturing → ready) — without it in
        // the signature the panel keeps the height measured for the previous
        // state and clips the new content.
        let transformerState: LauncherViewModel.TransformerState
        let chatExpanded: Bool
        // The composer grows with wrapped/newlined drafts and the error
        // row appears/disappears — both change the panel height.
        let chatInput: String
        let chatError: String?
    }

    override private init() {
        super.init()
        // Apps installed while Trast runs: the scanner's directory watcher
        // refreshes the cache in the background; if the panel is open, pick
        // up the new items live, otherwise the next open reads the fresh cache.
        appsUpdateObserver = NotificationCenter.default.addObserver(
            forName: AppScanner.appsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.panel?.isVisible == true else { return }
            self.viewModel.items = self.makeItems()
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    /// Opens the launcher on the bare search bar (nil) or directly on a
    /// category (tool hotkeys). The category is applied BEFORE the panel is
    /// sized: the sync resize must measure the final content — sizing the
    /// reset state first left the panel at bare-search height and the async
    /// observer pass then raced the signature/frame caches (see
    /// resizePanelToFit), leaving the panel stuck on a clipped search box.
    func show(_ category: LauncherViewModel.Category? = nil) {
        target = WindowManipulator.frontmostWindow()
        viewModel.items = makeItems()
        viewModel.reset()
        if let category {
            viewModel.selectCategory(category)
        }

        let panel = ensurePanel()
        // A stale frame from the previous session (e.g. a one-row search
        // result) must never leak into this open: bypass the signature and
        // last-frame caches for the first pass.
        lastLayoutSignature = nil
        lastTargetFrame = nil
        resizePanelToFit()
        panel.makeKeyAndOrderFront(nil)
        // The sync measurement above can reflect the PRE-change layout when
        // the panel already existed (the hosting view hadn't applied the
        // reset/category switch yet) — the clipboard-hotkey "opens on an
        // empty search box" symptom: the list renders below a bare-search-
        // height panel. Re-measure once on the next turn with the settled
        // layout; a correct measurement hits the unchanged target frame
        // and stays put.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.lastLayoutSignature = nil
            self.resizePanelToFit()
        }
    }

    func showClipboard() {
        if panel?.isVisible == true, viewModel.selectedCategory == .clipboard {
            close()
        } else {
            show(.clipboard)
        }
    }

    func showScratchpad() {
        if panel?.isVisible == true, viewModel.selectedCategory == .scratchpad {
            close()
        } else {
            show(.scratchpad)
        }
    }

    private func makeItems() -> [LauncherItem] {
        var items: [LauncherItem] = []
        items.append(contentsOf: CommandStore.shared.commands.map { command in
            .command(command, hotkeyName: HotkeyManager.name(for: command.id))
        })
        items.append(contentsOf: WindowAction.all.map { action in
            .command(action.command, hotkeyName: HotkeyManager.actionName(action.id))
        })
        items.append(contentsOf: AppShortcutStore.shared.validShortcuts.filter { $0.kind != .app }.map { shortcut in
            .appShortcut(shortcut, hotkeyName: HotkeyManager.appJumpName(for: shortcut.id))
        })
        items.append(contentsOf: installedAppItems())
        items.append(contentsOf: LauncherAction.allCases.map { .launcherAction($0) })
        items.append(contentsOf: SnippetStore.shared.validSnippets.map { .snippetEntry($0) })
        items.append(contentsOf: ClipboardStore.shared.items.map { .clipboardEntry($0) })
        items.append(contentsOf: ColorStore.shared.colors.map { .colorEntry($0) })
        items.append(contentsOf: LauncherViewModel.Category.visibleCases.compactMap { category -> LauncherItem? in
            switch category {
            case .all, .trast:
                return nil
            default:
                return .categoryEntry(category)
            }
        })
        return items
    }

    private func installedAppItems() -> [LauncherItem] {
        let appShortcuts = AppShortcutStore.shared.validShortcuts.filter { $0.kind == .app }
        let shortcutByBundleID = Dictionary(uniqueKeysWithValues: appShortcuts.compactMap { s in
            s.bundleIdentifier.map { ($0, s) }
        })
        let shortcutByPath = Dictionary(uniqueKeysWithValues: appShortcuts.compactMap { s in
            s.bundleURL.map { ($0.path, s) }
        })

        return AppScanner.cachedApps().map { app in
            let existingShortcut = shortcutByBundleID[app.bundleIdentifier ?? ""]
                ?? shortcutByPath[app.bundleURL.path]
            let hotkeyName: KeyboardShortcuts.Name
            if let existingShortcut {
                hotkeyName = HotkeyManager.appJumpName(for: existingShortcut.id)
            } else {
                hotkeyName = KeyboardShortcuts.Name("installedApp.\(app.id)")
            }
            return LauncherItem.installedApp(app, hotkeyName: hotkeyName)
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Entering the transformer captures the selection: Accessibility first
    /// (works while the panel is open), pasteboard borrow as fallback — the
    /// panel is hidden for the synthetic Cmd+C, since posted keyboard events
    /// go to the app owning the key window, which is Trast while the panel
    /// is up. The panel is brought back when the fallback completes.
    func enterTextTransformer() {
        viewModel.beginTextTransformerCapture()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let axText = TextTransformerController.shared.axSelectedText()
            if let axText, !axText.isEmpty {
                DispatchQueue.main.async {
                    self.finishTransformerCapture(axText)
                }
                return
            }
            DispatchQueue.main.async {
                self.panel?.orderOut(nil)
            }
            TextTransformerController.shared.captureViaPasteboard { [weak self] text in
                DispatchQueue.main.async {
                    self?.panel?.makeKeyAndOrderFront(nil)
                    self?.finishTransformerCapture(text)
                }
            }
        }
    }

    private func finishTransformerCapture(_ text: String?) {
        viewModel.finishTextTransformerCapture(text)
    }

    func showTextTransformer() {
        if panel?.isVisible == true, viewModel.selectedCategory == .textTransformer {
            close()
        } else {
            show(.textTransformer)
        }
    }

    func showAIChat() {
        if panel?.isVisible == true, viewModel.selectedCategory == .aiChat {
            close()
        } else {
            show(.aiChat)
        }
    }

    func showColorPicker() {
        if panel?.isVisible == true, viewModel.selectedCategory == .colorPicker {
            close()
        } else {
            show(.colorPicker)
        }
    }

    /// The system eyedropper: saves the picked color and reopens the
    /// launcher on the saved-colors list (newest on top). The panel is
    /// closed before this runs — the sampler samples the screen.
    func pickColorFromScreen() {
        NSColorSampler().show { [weak self] color in
            guard let self, let color else { return } // nil = cancelled
            let hex = ColorStore.hexString(from: color)
            ColorStore.shared.add(hex: hex)
            HUD.show("Saved \(hex)")
            self.show(.colorPicker)
        }
    }

    /// Applies the highlighted transformation to the captured selection:
    /// closes the panel first (the target app stays frontmost — the panel
    /// is non-activating), then replaces the selection and shows feedback.
    func applySelectedTransform() {
        guard viewModel.selectedCategory == .textTransformer,
              let transform = viewModel.selectedTransform() else { return }
        let text = viewModel.transformerText
        close()
        TextTransformerController.shared.apply(transform, to: text)
        HUD.show("Selection replaced")
    }

    func handleEscape() {
        if viewModel.selectedCategory != .all {
            // From a tool or category, back to the All search.
            viewModel.selectCategory(.all)
        } else if !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
            // A typed search: clear it back to the main (empty or tools)
            // view — not straight out of the launcher.
            viewModel.query = ""
        } else {
            // Empty search: close immediately.
            close()
        }
    }

    /// Rebuilds the launcher item list after a store change (adding or
    /// removing a shortcut from the options modal).
    func refreshItems() {
        viewModel.items = makeItems()
    }

    /// Cmd+K (or the row context menu) opens the options modal on the
    /// highlighted row: favorites, add-as-shortcut, hotkey editing, and
    /// snippet editing without a trip to Settings.
    private func showOptionsForSelectedItem() {
        guard viewModel.selectedCategory != .scratchpad,
              let item = viewModel.selectedItem(),
              viewModel.isFavoritable(item) else { return }
        viewModel.openOptions(for: item.id)
    }

    /// Closes the launcher and opens Settings on the Snippets tab — the
    /// handoff from the Add New Snippet row and the options modal's
    /// "Edit in Settings…".
    func openSnippetsSettings() {
        close()
        SettingsWindow.pendingSection = .snippets
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    /// Closes the launcher and opens Settings on the Shortcuts tab with the
    /// given shortcut selected — the "continue in Settings" handoff from
    /// the options modal's Add as Shortcut.
    func openSettingsRevealingShortcut(_ shortcutID: UUID) {
        close()
        SettingsWindow.pendingSection = .shortcuts
        SettingsWindow.pendingShortcutID = shortcutID
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    private func handle(_ item: LauncherItem) {
        UsageTracker.shared.record(item.id)
        switch item {
        case .command(let command, _):
            close()
            CommandApplier.shared.apply(command, target: target ?? WindowManipulator.frontmostWindow())
        case .appShortcut(let shortcut, _):
            close()
            AppShortcutStore.shared.activate(shortcut.id)
        case .installedApp(let app, _):
            close()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.hides = false
            NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration) { runningApp, error in
                if let error {
                    Task { @MainActor in HUD.show(error.localizedDescription) }
                    return
                }
                runningApp?.activate(options: [.activateAllWindows])
            }
        case .launcherAction(let action):
            if case .clipboardHistory = action {
                viewModel.selectCategory(.clipboard)
                return
            }
            if case .pickColor = action {
                close()
                pickColorFromScreen()
                return
            }
            if case .addSnippet = action {
                openSnippetsSettings()
                return
            }
            close()
            switch action {
            case .settings:
                openSettingsWindow()
            case .checkForUpdates:
                UpdateChecker.checkForUpdates()
            case .quit:
                NSApp.terminate(nil)
            case .clipboardHistory, .pickColor, .addSnippet:
                break
            }
        case .clipboardEntry(let item):
            close()
            pasteClipboardItem(item)
        case .colorEntry(let color):
            // Return copies the hex; rgb/hsl live on the row's context menu.
            close()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(color.hex, forType: .string)
            HUD.show("Copied \(color.hex)")
        case .snippetEntry(let snippet):
            close()
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let resolved = SnippetTemplate.resolve(snippet.content, clipboardContent: clipboard)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(resolved, forType: .string)
            HUD.show("Snippet copied to clipboard")
        case .calculatorResult(_, _, let value):
            close()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            HUD.show("Copied")
        case .categoryEntry(let category):
            viewModel.selectCategory(category)
        case .toolEntry(let category, _):
            viewModel.selectCategory(category)
        }
    }

    private func ensurePanel() -> LauncherPanel {
        if let panel { return panel }

        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hostingView = NSHostingView(
            rootView: LauncherView(viewModel: viewModel) { [weak self] item in
                self?.handle(item)
            }
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        self.panel = panel
        installKeyMonitor()
        observeContentChanges()
        return panel
    }

    private func observeContentChanges() {
        resizeCancellable = viewModel.objectWillChange.sink { [weak self] _ in
            // One input change fires objectWillChange several times (query,
            // selection, results); coalesce them into a single resize pass.
            guard let self, !self.resizeScheduled else { return }
            self.resizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                // The measurement can lag one turn behind the state change
                // (e.g. ↓ opening the tools view); a pass that came up with
                // the previous frame re-measures once after the layout has
                // settled. A pass that measured the real content no-ops
                // through the signature cache.
                if self.resizePanelToFit() {
                    DispatchQueue.main.async { self.resizePanelToFit() }
                }
            }
        }
    }

    /// Resizes the panel to its content. Returns true when the measurement
    /// produced the previous frame with a NEW signature — the layout may
    /// have lagged one turn behind the state change (fittingSize can
    /// reflect the pre-change content), so the caller re-checks once.
    @discardableResult
    private func resizePanelToFit() -> Bool {
        guard let panel, let hostingView = panel.contentView as? NSHostingView<LauncherView> else { return false }

        let signature = LayoutSignature(
            category: viewModel.selectedCategory,
            sectionTitles: viewModel.sections.map(\.title),
            rowCount: viewModel.filtered.count,
            transformerState: viewModel.transformerState,
            chatExpanded: viewModel.chatExpanded,
            chatInput: viewModel.chatInput,
            chatError: viewModel.chatError
        )
        // The content height can't have changed (selection move, hover);
        // skip the fittingSize measurement, which forces a full layout pass.
        if signature == lastLayoutSignature, lastTargetFrame != nil { return false }

        let fittingSize = hostingView.fittingSize
        // The expanded Quick AI view sizes itself to the viewport; everything
        // else caps at the previous 440.
        let cap: CGFloat = viewModel.chatExpanded ? .greatestFiniteMagnitude : 440
        var height = min(fittingSize.height, cap)
        height = max(height, 52)
        guard let target = targetFrame(width: LauncherViewModel.panelWidth(for: viewModel.selectedCategory), height: height) else { return false }
        // Skip when the destination is unchanged: objectWillChange fires on
        // every keystroke and selection move, and restarting the easeInOut
        // resize from a mid-flight frame makes the panel visibly stutter.
        guard target != lastTargetFrame else { return true }
        // Cache the signature only once a frame matches it. This pass may
        // have measured the PRE-change layout (fittingSize can lag the
        // state change by a turn); caching the new signature with the old
        // frame would make every later pass skip above and leave the panel
        // stuck at the old height for good — the "tool hotkey opens a
        // bare search box that won't do anything" symptom.
        lastLayoutSignature = signature
        lastTargetFrame = target

        // Animate only large jumps (mode switches) in sync with
        // LauncherViewModel.modeAnimation: an instant setContentSize of that
        // size lets the window's material layer draw square corners for a
        // frame before SwiftUI re-applies the corner mask. Small deltas
        // (search results growing/shrinking) snap, which reads as smooth
        // incremental tracking and avoids animation pile-up while typing.
        if panel.isVisible, abs(target.height - panel.frame.height) > 60 || abs(target.width - panel.frame.width) > 60 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
        return false
    }

    private func targetFrame(width: CGFloat, height: CGFloat) -> NSRect? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return nil }
        let visible = screen.visibleFrame
        let scale = screen.backingScaleFactor
        // Pixel-align size and origin to avoid sub-pixel jitter on non-HiDPI displays.
        let alignedWidth = (width * scale).rounded() / scale
        let alignedHeight = (height * scale).rounded() / scale
        let x = visible.midX - alignedWidth / 2
        // Never target below the visible frame: a panel taller than the
        // 32% slot pushed y negative and AppKit clamped the window to the
        // bottom edge of the screen.
        let y = max(visible.minY, visible.maxY - visible.height * 0.32 - alignedHeight)
        let alignedX = (x * scale).rounded() / scale
        let alignedY = (y * scale).rounded() / scale
        return NSRect(x: alignedX, y: alignedY, width: alignedWidth, height: alignedHeight)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow else { return event }

            if event.modifierFlags.contains(.command), event.keyCode == 43 {
                self.close()
                self.openSettingsWindow()
                return nil
            }

            // Options modal (Cmd+K): arrows + Return drive its actions;
            // everything else passes through so the hotkey recorder keeps
            // receiving raw keystrokes.
            if self.viewModel.optionsItemID != nil {
                if event.keyCode == 53 {
                    self.viewModel.optionsItemID = nil
                    return nil
                }
                if event.modifierFlags.contains(.command), event.keyCode == 40 {
                    self.viewModel.optionsItemID = nil
                    return nil
                }
                if event.keyCode == 125 {
                    self.viewModel.moveOptionsSelection(1)
                    return nil
                }
                if event.keyCode == 126 {
                    self.viewModel.moveOptionsSelection(-1)
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.viewModel.activateSelectedOption()
                    return nil
                }
                return event
            }

            if event.modifierFlags.contains(.command) {
                let numberKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
                if let index = numberKeyCodes.firstIndex(of: event.keyCode) {
                    self.viewModel.selectCategoryByIndex(index)
                    return nil
                }
                // Cmd+K — options for the highlighted row, the keyboard
                // equivalent of the right-click context menu.
                if event.keyCode == 40 {
                    self.showOptionsForSelectedItem()
                    return nil
                }
            }

            // AI Chat: typing and Return reach the message field; Cmd+N
            // starts a new discussion. Return sends, Shift+Return inserts a
            // newline — both swallowed before the field (macOS fires
            // onSubmit for Shift+Return too). Esc/Tab are launcher
            // navigation.
            if self.viewModel.selectedCategory == .aiChat {
                if event.modifierFlags.contains(.command), event.keyCode == 45 {
                    self.viewModel.createNewChatDiscussion()
                    return nil
                }
                switch event.keyCode {
                case 53:
                    self.handleEscape()
                    return nil
                case 48:
                    self.handleEscape()
                    return nil
                case 36, 76:
                    if event.modifierFlags.contains(.shift) {
                        self.viewModel.chatInput += "\n"
                    } else {
                        self.viewModel.sendChatMessage()
                    }
                    return nil
                default:
                    return event
                }
            }

            // Text Transformer mode: arrows pick a transformation, Return
            // replaces the selection, everything else is swallowed (there
            // is no text field to receive typing).
            if self.viewModel.selectedCategory == .textTransformer {
                switch event.keyCode {
                case 125:
                    self.viewModel.moveTransformSelection(1)
                    return nil
                case 126:
                    self.viewModel.moveTransformSelection(-1)
                    return nil
                case 36, 76:
                    self.applySelectedTransform()
                    return nil
                case 53:
                    self.handleEscape()
                    return nil
                case 48:
                    self.handleEscape()
                    return nil
                default:
                    return nil
                }
            }

            // Scratchpad: the editor needs Return, arrows, and all text
            // keys; only Esc and Tab are launcher navigation. Cmd+N creates
            // a note. The notes sidebar is click-driven.
            if self.viewModel.selectedCategory == .scratchpad {
                if event.modifierFlags.contains(.command), event.keyCode == 45 {
                    self.viewModel.createNote()
                    return nil
                }
                switch event.keyCode {
                case 53:
                    self.handleEscape()
                    return nil
                case 48:
                    self.handleEscape()
                    return nil
                default:
                    return event
                }
            }

            switch event.keyCode {
            case 48:
                // Tab opens the unified tools/recents view — same as ↓ and
                // the search bar's list button — when the search is empty;
                // otherwise it walks the list like ↓ (Shift+Tab like ↑).
                if self.viewModel.selectedCategory == .all,
                   self.viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty,
                   self.viewModel.filtered.isEmpty {
                    if !event.modifierFlags.contains(.shift) {
                        self.viewModel.showRecentActivity()
                    }
                    return nil
                }
                self.viewModel.moveSelection(event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            case 123, 124, 125, 126:
                if event.keyCode == 125 {
                    // Down from an empty All search opens the tools/recents
                    // view instead of doing nothing.
                    if self.viewModel.selectedCategory == .all,
                       self.viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty,
                       self.viewModel.filtered.isEmpty {
                        self.viewModel.showRecentActivity()
                        return nil
                    }
                    self.viewModel.moveSelection(1)
                    return nil
                }
                if event.keyCode == 126 {
                    self.viewModel.moveSelection(-1)
                    return nil
                }
                return event
            case 36, 76:
                if let item = self.viewModel.selectedItem() {
                    self.handle(item)
                }
                return nil
            case 53:
                self.handleEscape()
                return nil
            default:
                return event
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func openSettingsWindow() {
        // The observer on the menu-bar label (StatusBarLabel) owns the full
        // open sequence — the .menu-style MenuBarExtra content that used to
        // observe this is only instantiated while the menu is open, so it
        // never fired from here.
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    private func pasteClipboardItem(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .tiff)
            }
        case .fileURL:
            if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
