import Foundation
import KeyboardShortcuts
import TrastCore
import AppKit
import SwiftUI

enum LauncherAction: String, CaseIterable, Identifiable {
    case settings
    case clipboardHistory
    case pickColor
    case addSnippet
    case checkForUpdates
    case quit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .clipboardHistory: return "Clipboard History"
        case .pickColor: return "Pick Color from Screen"
        case .addSnippet: return "Add New Snippet"
        case .checkForUpdates: return "Check for Updates"
        case .quit: return "Quit Trast"
        }
    }

    var icon: String {
        switch self {
        case .settings: return "gearshape"
        case .clipboardHistory: return "clipboard"
        case .pickColor: return "eyedropper"
        case .addSnippet: return "plus.square.on.square"
        case .checkForUpdates: return "arrow.clockwise.circle"
        case .quit: return "power"
        }
    }

}

enum LauncherIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    /// Saved-color swatches, cached by hex so rows don't re-render their
    /// drawing handler on every pass.
    static func colorSwatch(for color: SavedColor) -> NSImage? {
        let key = "swatch.\(color.hex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            ColorStore.nsColor(for: color.hex).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5).fill()
            // A faint border so white swatches survive light backgrounds.
            NSColor.controlTextColor.withAlphaComponent(0.15).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
            border.lineWidth = 1
            border.stroke()
            return true
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Decoded clipboard thumbnails, cached by entry id so image rows don't
    /// re-decode their data on every render.
    static func clipboardImage(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let data = item.imageData else { return nil }
        let key = item.id.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

enum LauncherItem: Identifiable {
    case command(WindowCommand, hotkeyName: KeyboardShortcuts.Name)
    case appShortcut(AppShortcut, hotkeyName: KeyboardShortcuts.Name)
    case installedApp(AppChooserItem, hotkeyName: KeyboardShortcuts.Name)
    case launcherAction(LauncherAction)
    case clipboardEntry(ClipboardItem)
    case snippetEntry(Snippet)
    case colorEntry(SavedColor)
    case categoryEntry(LauncherViewModel.Category)
    case toolEntry(LauncherViewModel.Category, number: Int)
    case calculatorResult(title: String, subtitle: String, valueToCopy: String)

    var id: String {
        switch self {
        case .command(_, let name), .appShortcut(_, let name), .installedApp(_, let name):
            return name.rawValue
        case .launcherAction(let action):
            return "launcherAction.\(action.rawValue)"
        case .clipboardEntry(let item):
            return "clipboard.\(item.id.uuidString)"
        case .snippetEntry(let snippet):
            return "snippet.\(snippet.id.uuidString)"
        case .colorEntry(let color):
            return "color.\(color.id.uuidString)"
        case .categoryEntry(let category):
            return "category.\(category.rawValue)"
        case .toolEntry(let category, _):
            return "tool.\(category.rawValue)"
        case .calculatorResult:
            return "calculator"
        }
    }

    var title: String {
        switch self {
        case .command(let command, _):
            return command.name
        case .appShortcut(let shortcut, _):
            return shortcut.name
        case .installedApp(let app, _):
            return app.name
        case .launcherAction(let action):
            return action.title
        case .clipboardEntry(let item):
            return item.displayName
        case .snippetEntry(let snippet):
            return snippet.name
        case .colorEntry(let color):
            return color.hex
        case .categoryEntry(let category):
            return category.label
        case .toolEntry(let category, _):
            return category.label
        case .calculatorResult(let title, _, _):
            return title
        }
    }

    var hotkeyName: KeyboardShortcuts.Name? {
        switch self {
        case .command(_, let name), .appShortcut(_, let name), .installedApp(_, let name):
            return name
        case .launcherAction, .clipboardEntry, .snippetEntry, .colorEntry, .categoryEntry, .toolEntry, .calculatorResult:
            return nil
        }
    }

    var icon: String {
        switch self {
        case .command:
            return "macwindow"
        case .appShortcut(let shortcut, _):
            switch shortcut.kind {
            case .app: return "arrow.right.square"
            case .url: return "link"
            case .folder: return "folder"
            }
        case .installedApp:
            return "app"
        case .launcherAction(let action):
            return action.icon
        case .clipboardEntry(let item):
            switch item.kind {
            case .text: return "text.alignleft"
            case .image: return "photo"
            case .fileURL: return "doc"
            }
        case .snippetEntry:
            return "text.append"
        case .colorEntry:
            return "eyedropper"
        case .categoryEntry(let category):
            return category.icon
        case .toolEntry(let category, _):
            return category.icon
        case .calculatorResult:
            return "plus.forwardslash.minus"
        }
    }

    var iconImage: NSImage? {
        switch self {
        case .installedApp(let app, _):
            return app.icon
        case .clipboardEntry(let item):
            return LauncherIconCache.clipboardImage(for: item)
        case .colorEntry(let color):
            return LauncherIconCache.colorSwatch(for: color)
        case .command, .appShortcut, .launcherAction, .snippetEntry, .categoryEntry, .toolEntry, .calculatorResult:
            return nil
        }
    }

    var searchText: String {
        switch self {
        case .clipboardEntry(let item):
            return "\(title)\n\(item.preview)"
        default:
            return subtitle.map { "\(title)\n\($0)" } ?? title
        }
    }

    var section: String {
        switch self {
        case .command(_, let name):
            return name.rawValue.hasPrefix("action.") ? "Actions" : "Window Commands"
        case .appShortcut:
            return "Shortcuts"
        case .installedApp:
            return "Applications"
        case .launcherAction:
            return "Trast"
        case .clipboardEntry:
            return "Clipboard"
        case .snippetEntry:
            return "Snippets"
        case .colorEntry:
            return "Colors"
        case .categoryEntry:
            return "Browse"
        case .toolEntry:
            return "Tools"
        case .calculatorResult:
            return "Calculator"
        }
    }

    var subtitle: String? {
        switch self {
        case .clipboardEntry(let item):
            switch item.kind {
            case .text:
                let preview = item.preview
                return preview.count > 60 ? String(preview.prefix(60)) + "..." : preview
            case .fileURL:
                return item.fileURL?.path
            case .image:
                return nil
            }
        case .snippetEntry(let snippet):
            return snippet.keyword
        case .colorEntry(let color):
            return color.rgbText
        case .calculatorResult(_, let subtitle, _):
            return subtitle
        default:
            return nil
        }
    }
}

struct LauncherSection: Identifiable {
    let title: String
    let items: [LauncherItem]
    var id: String { title }
}

final class LauncherViewModel: ObservableObject {

    /// A launch candidate with everything the search path needs resolved once
    /// when the item list is built, instead of on every keystroke.
    private struct SearchEntry {
        let item: LauncherItem
        let section: String
        let hotkeyDisplay: String?
    }
    enum Category: String, CaseIterable, Hashable {
        case all
        case commands
        case shortcuts
        case applications
        case clipboard
        case snippets
        case scratchpad
        case trast
        case textTransformer
        case aiChat
        case colorPicker

        var label: String {
            switch self {
            case .all: return "All"
            case .commands: return "Window Commands"
            case .shortcuts: return "Shortcuts"
            case .applications: return "Apps"
            case .clipboard: return "Clipboard"
            case .snippets: return "Snippets"
            case .scratchpad: return "Scratchpad"
            case .trast: return "Trast"
            case .textTransformer: return "Text Transformer"
            case .aiChat: return "AI Chat"
            case .colorPicker: return "Color Picker"
            }
        }

        var icon: String {
            switch self {
            case .all: return "magnifyingglass"
            case .commands: return "macwindow"
            case .shortcuts: return "arrow.right.square"
            case .applications: return "app"
            case .clipboard: return "clipboard"
            case .snippets: return "text.append"
            case .scratchpad: return "square.and.pencil"
            case .trast: return "gearshape"
            case .textTransformer: return "textformat"
            case .aiChat: return "sparkles"
            case .colorPicker: return "eyedropper"
            }
        }

        static var visibleCases: [Category] {
            var cases: [Category] = [.all, .commands, .shortcuts, .applications]
            if AppSettings.launcherClipboardTab { cases.append(.clipboard) }
            if AppSettings.launcherSnippetsTab { cases.append(.snippets) }
            cases.append(.scratchpad)
            cases.append(.textTransformer)
            cases.append(.aiChat)
            cases.append(.colorPicker)
            cases.append(.trast)
            return cases
        }

        /// The tools listed in the unified tools view and addressed by
        /// Cmd+1..n. Apps is the first entry; the rest follow the settings
        /// tab toggles.
        static var toolCases: [Category] {
            var cases: [Category] = [.applications]
            if AppSettings.launcherClipboardTab { cases.append(.clipboard) }
            cases.append(.colorPicker)
            if AppSettings.launcherSnippetsTab { cases.append(.snippets) }
            cases.append(.scratchpad)
            cases.append(.textTransformer)
            cases.append(.aiChat)
            return cases
        }
    }

    private static let placeholders = [
        "What do you want to do?",
        "Search commands, apps, and more...",
        "Type to search...",
        "What's next?",
        "Search everything...",
        "What are you looking for?",
    ]

    @Published var placeholder: String = placeholders[0]
    @Published var selectedCategory: Category = .all {
        didSet { selectedIndex = 0; updateResults() }
    }
    @Published var query = "" {
        didSet { selectedIndex = 0; updateResults() }
    }
    @Published var selectedIndex = 0
    @Published var focusToken = UUID()
    @Published var showsRecentActivity = false
    /// The hovered result row, tracked here (not per-row @State): rows are
    /// reused across section changes under the same identity, where @State
    /// can survive a missed hover-exit and stay stuck highlighted.
    @Published var hoveredID: String?
    /// The row whose options modal (Cmd+K) is open, and the keyboard
    /// selection within it.
    @Published var optionsItemID: String?
    @Published var optionsSelectedIndex = 0

    /// An activatable row in the options modal (the hotkey recorder is
    /// rendered separately and stays mouse-driven).
    enum OptionsAction: Identifiable {
        case favorite
        case addShortcut
        case removeShortcut
        case editSnippet

        var id: String {
            switch self {
            case .favorite: return "favorite"
            case .addShortcut: return "addShortcut"
            case .removeShortcut: return "removeShortcut"
            case .editSnippet: return "editSnippet"
            }
        }
    }

    /// The row the modal applies to, resolved against the current results
    /// (a stale id closes the modal).
    var optionsItem: LauncherItem? {
        guard let id = optionsItemID else { return nil }
        return filtered.first { $0.id == id }
    }

    var optionsActions: [OptionsAction] {
        guard let item = optionsItem else { return [] }
        var actions: [OptionsAction] = []
        if isFavoritable(item) {
            actions.append(.favorite)
        }
        if case .snippetEntry = item {
            actions.append(.editSnippet)
        }
        if case .installedApp(_, let name) = item, name.rawValue.hasPrefix("installedApp.") {
            actions.append(.addShortcut)
        }
        if underlyingShortcut(for: item) != nil {
            actions.append(.removeShortcut)
        }
        return actions
    }

    func openOptions(for id: String) {
        if optionsItemID == id {
            optionsItemID = nil
        } else {
            optionsItemID = id
            optionsSelectedIndex = 0
        }
    }

    func moveOptionsSelection(_ delta: Int) {
        let count = optionsActions.count
        guard count > 0 else { return }
        optionsSelectedIndex = (optionsSelectedIndex + delta + count) % count
    }

    func activateSelectedOption() {
        guard let action = optionsActions[safe: optionsSelectedIndex],
              let item = optionsItem else { return }
        switch action {
        case .favorite:
            toggleFavorite(item.id)
        case .addShortcut:
            // Create the shortcut (name autofilled) and hand off to Settings
            // on the new shortcut so the hotkey can be recorded there.
            guard case .installedApp(let app, _) = item else { return }
            let added = AppShortcutStore.shared.add(app.appShortcut)
            optionsItemID = nil
            LauncherController.shared.openSettingsRevealingShortcut(added.id)
        case .removeShortcut:
            guard let shortcut = underlyingShortcut(for: item) else { return }
            AppShortcutStore.shared.remove(shortcut)
            LauncherController.shared.refreshItems()
            optionsItemID = nil
        case .editSnippet:
            // Snippets are managed in Settings; this is the modal's handoff.
            optionsItemID = nil
            LauncherController.shared.openSnippetsSettings()
        }
    }

    /// The AppShortcut behind a row, when there is one.
    func underlyingShortcut(for item: LauncherItem) -> AppShortcut? {
        switch item {
        case .appShortcut(let shortcut, _):
            return shortcut
        case .installedApp(let app, let name) where name.rawValue.hasPrefix("appJump."):
            return AppShortcutStore.shared.validShortcuts.first {
                $0.kind == .app
                    && ($0.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier
                        || $0.bundleURL?.path == app.bundleURL.path)
            }
        default:
            return nil
        }
    }

    /// The composer draft and send state live here (not view @State) so
    /// the LauncherController key monitor can drive the keyboard: Return
    /// sends, Shift+Return inserts a newline, and the panel-height
    /// LayoutSignature tracks the vertically growing field.
    @Published var chatInput = ""
    @Published var chatSending = false
    @Published var chatError: String?
    /// Quick AI's expand toggle: normal launcher-sized panel vs ~80% of
    /// the viewport for long conversations.
    @Published var chatExpanded = false

    /// The Text Transformer tool captures the frontmost app's selection on
    /// entry and previews transformations over it.
    enum TransformerState {
        case capturing
        case noSelection
        case ready
    }

    @Published var transformerState: TransformerState = .capturing
    @Published var transformerText: String = ""
    @Published var transformSelectedIndex = 0
    /// The enabled transformations in the user's chosen order
    /// (Settings → Text Transformer), loaded on tool entry.
    @Published var transforms: [TextTransform] = []
    @Published private(set) var filtered: [LauncherItem] = []
    @Published private(set) var sections: [LauncherSection] = []
    /// Mirrors `FavoritesStore` so rows re-render when a favorite toggles.
    @Published private(set) var favorites: Set<String> = FavoritesStore.shared.ids

    @Published var items: [LauncherItem] = [] {
        didSet { rebuildIndex(); updateResults() }
    }

    /// Precomputed search index: item list → search text, lowercased matching
    /// buffer, section, and resolved hotkey label, all computed once per
    /// item-list rebuild (every panel open) instead of per keystroke.
    private var index: [FuzzyMatch.Indexed<SearchEntry>] = []

    /// Hotkey display strings keyed by `LauncherItem.id` (which is the
    /// `KeyboardShortcuts.Name` for hotkey-carrying items).
    private var hotkeyDisplays: [String: String] = [:]

    func hotkeyDisplay(for item: LauncherItem) -> String? {
        guard let name = item.hotkeyName else { return nil }
        return hotkeyDisplays[name.rawValue]
    }

    private func rebuildIndex() {
        hotkeyDisplays.removeAll()
        index = items.map { item in
            let hotkeyDisplay = item.hotkeyName.flatMap {
                KeyboardShortcuts.getShortcut(for: $0)?.hyperDescription
            }
            if let hotkeyDisplay, let name = item.hotkeyName {
                hotkeyDisplays[name.rawValue] = hotkeyDisplay
            }
            let entry = SearchEntry(item: item, section: item.section, hotkeyDisplay: hotkeyDisplay)
            return FuzzyMatch.Indexed(item: entry, text: item.searchText)
        }
    }

    func reset() {
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        selectedCategory = .all
        optionsItemID = nil
        query = ""
        selectedIndex = 0
        focusToken = UUID()
        showsRecentActivity = false
        favorites = FavoritesStore.shared.ids
    }

    // MARK: - Scratchpad notes

    /// Cmd+N / the New button: a fresh empty note, opened in the editor.
    func createNote() {
        NotesStore.shared.createNote()
        focusToken = UUID()
    }

    /// Opens a note from the sidebar in the editor.
    func openNote(_ id: UUID) {
        NotesStore.shared.open(id: id)
        focusToken = UUID()
    }

    // MARK: - AI Chat

    func createNewChatDiscussion() {
        ChatStore.shared.newDiscussion()
        focusToken = UUID()
    }

    func openSelectedDiscussionID(_ id: UUID) {
        ChatStore.shared.open(id: id)
        focusToken = UUID()
    }

    /// Sends the composer draft. Keyboard dispatch lives in the
    /// LauncherController key monitor (Return sends, Shift+Return inserts
    /// a newline); the send button calls this directly.
    func sendChatMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatSending else { return }
        chatError = nil
        chatInput = ""
        ChatStore.shared.appendToCurrent(ChatMessage(role: .user, text: text))
        chatSending = true
        let messages = ChatStore.shared.currentMessages
        Task { @MainActor in
            do {
                let reply = try await ChatService.send(messages: messages)
                ChatStore.shared.appendToCurrent(ChatMessage(role: .assistant, text: reply))
            } catch {
                chatError = error.localizedDescription
            }
            chatSending = false
        }
    }

    func deleteDiscussion(at index: Int) {
        guard let discussion = ChatStore.shared.discussions[safe: index] else { return }
        ChatStore.shared.delete(id: discussion.id)
    }

    // MARK: - Text Transformer

    /// Entering the tool clears state and starts capturing the frontmost
    /// app's selection (orchestrated by `LauncherController`, which owns the
    /// panel — the pasteboard fallback needs it hidden).
    func beginTextTransformerCapture() {
        transformerState = .capturing
        transformerText = ""
        transformSelectedIndex = 0
        transforms = AppSettings.orderedTransforms
    }

    func finishTextTransformerCapture(_ text: String?) {
        guard selectedCategory == .textTransformer else { return }
        if let text, !text.isEmpty {
            transformerText = text
            transformerState = .ready
        } else {
            transformerState = .noSelection
        }
    }

    func moveTransformSelection(_ delta: Int) {
        let count = transforms.count
        guard count > 0 else { return }
        transformSelectedIndex = (transformSelectedIndex + delta + count) % count
    }

    func selectedTransform() -> TextTransform? {
        guard transformerState == .ready else { return nil }
        return transforms[safe: transformSelectedIndex]
    }

    /// Opens the recent-activity view (↓ with an empty query in All):
    /// favorites first, then the last-used items across everything.
    func showRecentActivity() {
        showsRecentActivity = true
        updateResults()
    }

    func isFavoritable(_ item: LauncherItem) -> Bool {
        switch item {
        case .calculatorResult, .clipboardEntry, .colorEntry, .categoryEntry, .toolEntry:
            return false
        default:
            return true
        }
    }

    func isFavorite(_ item: LauncherItem) -> Bool {
        guard isFavoritable(item) else { return false }
        return favorites.contains(item.id)
    }

    func toggleFavorite(_ id: String) {
        FavoritesStore.shared.toggle(id)
        favorites = FavoritesStore.shared.ids
        updateResults()
    }

    /// Recomputes `filtered` and `sections` exactly once per input change.
    /// These are read repeatedly by the view body (once per row), so they are
    /// stored instead of computed. `filtered` is always the sections flattened
    /// in display order — the selection walks what's on screen, so no
    /// visible row can be skipped or visited out of order.
    private func updateResults() {
        hoveredID = nil
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            if selectedCategory == .all {
                if showsRecentActivity {
                    // The unified tools view: only the tool rows. Favorites
                    // and recent items were tiers here once — they moved to
                    // their own surfaces, search still finds everything.
                    let toolItems = Self.toolEntries()
                    sections = [LauncherSection(title: "Tools", items: toolItems)]
                    filtered = toolItems
                } else {
                    filtered = []
                    sections = []
                }
                return
            }
            let recent = recentItems(for: selectedCategory)
            sections = Self.makeSections(from: recent)
            filtered = sections.flatMap { $0.items }
            return
        }

        // Scope to the category before ranking so an Apps search doesn't
        // fuzzy-score commands, snippets, and clipboard items.
        let scoped = index.filter { includesInCategory($0.item) }
        var ranked: [LauncherItem] = FuzzyMatch.rankedIndexed(scoped, query: query).map { $0.item.item }

        // Calculations (math, units, currency) show above other results in
        // the All category. Parsing is O(query length); the rates autoclosure
        // only evaluates when the query looks like a currency conversion.
        if selectedCategory == .all,
           let calc = Calculator.parse(
            query: trimmed,
            rates: ExchangeRateStore.shared.currentRates(),
            baseCurrency: AppSettings.baseCurrency,
            preferredUnits: AppSettings.preferredUnits
           ) {
            ranked.insert(.calculatorResult(
                title: calc.display,
                subtitle: calc.subtitle,
                valueToCopy: calc.clipboardValue
            ), at: 0)
        }
        sections = Self.makeSections(from: ranked)
        filtered = sections.flatMap { $0.items }
    }

    private func includesInCategory(_ entry: SearchEntry) -> Bool {
        switch selectedCategory {
        case .all:
            return entry.section != "Clipboard" && entry.section != "Snippets" && entry.section != "Colors"
        case .commands:
            return entry.section == "Window Commands" || entry.section == "Actions"
        case .shortcuts:
            return entry.section == "Shortcuts"
        case .applications:
            return entry.section == "Applications"
        case .clipboard:
            return entry.section == "Clipboard"
        case .snippets:
            return entry.section == "Snippets"
        case .scratchpad:
            return false
        case .trast:
            if case .launcherAction(.clipboardHistory) = entry.item { return false }
            return entry.section == "Trast"
        case .textTransformer, .aiChat:
            return false
        case .colorPicker:
            return entry.section == "Colors"
        }
    }

    private static let sectionOrder = ["Calculator", "Browse", "Window Commands", "Actions", "Shortcuts", "Applications", "Clipboard", "Snippets", "Colors", "Trast"]

    private static func makeSections(from items: [LauncherItem]) -> [LauncherSection] {
        sectionOrder.compactMap { title in
            let sectionItems = items.filter { $0.section == title }
            return sectionItems.isEmpty ? nil : LauncherSection(title: title, items: sectionItems)
        }
    }

    /// The ↓ view: every tool as a compact row, ⌘-numbered in
    /// `Category.toolCases` order.
    private static func toolEntries() -> [LauncherItem] {
        Category.toolCases.enumerated().map { index, category in
            LauncherItem.toolEntry(category, number: index + 1)
        }
    }

    private func sortedByUsage(_ items: [LauncherItem]) -> [LauncherItem] {
        let ids = items.map(\.id)
        let recentIDs = UsageTracker.shared.sortedByRecent(ids)
        let idOrder = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($1, $0) })
        return items.sorted { a, b in
            let ia = idOrder[a.id] ?? Int.max
            let ib = idOrder[b.id] ?? Int.max
            if ia != ib { return ia < ib }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private func recentItems(for category: Category) -> [LauncherItem] {
        switch category {
        case .clipboard:
            return ClipboardStore.shared.items.map { .clipboardEntry($0) }
        case .snippets:
            // The add action leads the list; snippets follow.
            return [.launcherAction(.addSnippet)]
                + SnippetStore.shared.validSnippets.map { .snippetEntry($0) }
        case .colorPicker:
            // The pick action leads the list; saved colors follow, newest
            // first (the store keeps that order).
            return [.launcherAction(.pickColor)]
                + ColorStore.shared.colors.map { .colorEntry($0) }
        default:
            break
        }

        let categoryItems = index.filter { includesInCategory($0.item) }.map(\.item.item)
        return sortedByUsage(categoryItems)
    }

    /// Cmd+1..5: open the tool at that position in `toolCases` — the same
    /// numbers the tool rows in the recents view badge with.
    func selectCategoryByIndex(_ index: Int) {
        let cases = Category.toolCases
        guard index >= 0, index < cases.count else { return }
        selectCategory(cases[index])
    }

    func selectCategory(_ category: Category) {
        selectedCategory = category
        selectedIndex = 0
        query = ""
        focusToken = UUID()
        if category == .aiChat {
            chatExpanded = false
        }
        if category == .textTransformer {
            LauncherController.shared.enterTextTransformer()
        }
    }

    func setHovered(_ id: String, hovering: Bool) {
        if hovering {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    func moveSelection(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    func selectedItem() -> LauncherItem? {
        filtered[safe: selectedIndex]
    }
}
