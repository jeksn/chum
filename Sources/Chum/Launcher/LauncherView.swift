import ChumCore
import SwiftUI
import AppKit
import KeyboardShortcuts

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    let onSelect: (LauncherItem) -> Void
    @ObservedObject private var notesStore = NotesStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var chatStore = ChatStore.shared

    @FocusState private var isFocused: Bool
    @FocusState private var editorFocused: Bool
    @FocusState private var chatFocused: Bool

    @State private var showsCopied = false
    @State private var confirmDelete = false
    @State private var chatHasKey = false
    @State private var chatCopied = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.selectedCategory == .textTransformer {
                transformerTool
                    .transition(.toolSwitch)
            } else if viewModel.selectedCategory == .aiChat {
                aiChatTool
                    .transition(.toolSwitch)
            } else if viewModel.selectedCategory == .scratchpad {
                scratchpad
                    .transition(.toolSwitch)
            } else {
                searchField
                    .transition(.toolSwitch)

                if !viewModel.filtered.isEmpty {
                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.sections) { section in
                                    if shouldShowSectionHeader {
                                        HStack {
                                            Text(section.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 16)
                                                .padding(.top, 8)
                                                .padding(.bottom, 2)
                                            Spacer()
                                        }
                                    }
                                    ForEach(section.items) { item in
                                        LauncherRowView(
                                            viewModel: viewModel,
                                            item: item,
                                            canFavorite: viewModel.isFavoritable(item)
                                        )
                                            .onHover { hovering in
                                                viewModel.setHovered(item.id, hovering: hovering)
                                            }
                                            .onTapGesture { onSelect(item) }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 360)
                        .onChange(of: viewModel.selectedIndex) { index in
                            if let item = viewModel.filtered[safe: index] {
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                } else {
                    let trimmedQuery = viewModel.query.trimmingCharacters(in: .whitespaces)
                    if !trimmedQuery.isEmpty {
                        Text("No results for \u{201C}\(trimmedQuery)\u{201D}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if showsOptionsFooter {
                Divider()
                HStack {
                    Spacer()
                    Text("⌘K Options")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 16)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(
            width: LauncherViewModel.panelWidth(for: viewModel.selectedCategory),
            height: viewModel.selectedCategory == .aiChat && viewModel.chatExpanded
                ? chatExpandedHeight
                : nil,
            alignment: .top
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedCategory)
        .background(
            RoundedRectangle(cornerRadius: 12)
                // Dark mode uses the thicker material - genuinely darker
                // (Spotlight-like) while keeping its own translucency.
                // Light mode stays on the regular material; a darkening
                // overlay there read as flat grey and killed the
                // see-through effect in both modes.
                .fill(colorScheme == .dark ? .thickMaterial : .regularMaterial)
                .opacity(AppSettings.launcherSlightTransparency ? 0.85 : 1.0)
        )
        .overlay {
            if let item = viewModel.optionsItem {
                optionsModal(item)
            }
        }
        .ignoresSafeArea(edges: .all)
        .onAppear {
            DispatchQueue.main.async { focusActiveField() }
        }
        .onChange(of: viewModel.focusToken) { _ in
            DispatchQueue.main.async { focusActiveField() }
        }
        .onExitCommand { LauncherController.shared.handleEscape() }
    }

    private func focusActiveField() {
        if viewModel.selectedCategory == .scratchpad {
            editorFocused = true
        } else if viewModel.selectedCategory == .aiChat {
            chatFocused = true
        } else {
            isFocused = true
        }
    }

    /// Cmd+K / right-click options modal: favorites, add-as-shortcut, and
    /// hotkey editing on top of the launcher, no trip to Settings.
    private func optionsModal(_ item: LauncherItem) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { viewModel.optionsItemID = nil }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if let nsImage = item.iconImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: item.icon)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.optionsItemID = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close (Esc)")
                }
                .padding(12)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(viewModel.optionsActions.enumerated()), id: \.element.id) { index, action in
                        optionRow(action: action, index: index)
                    }

                    if let hotkeyName = item.hotkeyName, isEditableHotkey(hotkeyName) {
                        Divider()
                            .padding(.vertical, 4)
                        HotkeyRecorderView("Hotkey:", name: hotkeyName)
                    }
                }
                .padding(12)

                Divider()

                Text("↑↓ to move · Return to run · Esc to close")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2))
            )
        }
    }

    private func optionRow(action: LauncherViewModel.OptionsAction, index: Int) -> some View {
        Button {
            viewModel.optionsSelectedIndex = index
            viewModel.activateSelectedOption()
        } label: {
            HStack(spacing: 10) {
                Label(optionLabel(action), systemImage: optionIcon(action))
                    .foregroundStyle(action == .removeShortcut ? Color.red : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(index == viewModel.optionsSelectedIndex
                          ? Color.accentColor.opacity(0.25)
                          : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func optionLabel(_ action: LauncherViewModel.OptionsAction) -> String {
        switch action {
        case .favorite:
            return viewModel.isFavorite(viewModel.optionsItem!) ? "Remove from Favorites" : "Add to Favorites"
        case .addShortcut:
            return "Add as Shortcut…"
        case .removeShortcut:
            return "Remove Shortcut"
        case .editSnippet:
            return "Edit in Settings…"
        }
    }

    private func optionIcon(_ action: LauncherViewModel.OptionsAction) -> String {
        switch action {
        case .favorite:
            return viewModel.isFavorite(viewModel.optionsItem!) ? "star.slash" : "star"
        case .addShortcut:
            return "arrow.right.square"
        case .removeShortcut:
            return "trash"
        case .editSnippet:
            return "pencil"
        }
    }

    /// Hotkeys the modal can edit: shortcuts, window commands, actions —
    /// not the synthetic names plain installed apps carry.
    private func isEditableHotkey(_ name: KeyboardShortcuts.Name) -> Bool {
        let raw = name.rawValue
        return raw.hasPrefix("appJump.") || raw.hasPrefix("command.") || raw.hasPrefix("action.")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            // The menu-bar bird logo, in beak amber — the one fixed accent.
            Image(nsImage: StatusBarIcon.image)
                .foregroundStyle(Theme.beak)
            TextField(viewModel.placeholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($isFocused)
            Button {
                viewModel.showRecentActivity()
            } label: {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 22)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Show tools and recents (Tab or ↓)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var scratchpad: some View {
        HStack(alignment: .top, spacing: 0) {
            notesSidebar
            Divider()
            noteEditor
        }
        .onChange(of: viewModel.selectedCategory) { category in
            if category != .scratchpad {
                confirmDelete = false
            }
        }
    }

    /// The persistent notes sidebar — the old Cmd+P notes list, now always
    /// visible beside the editor. Click a row to open the note; right-click
    /// archives or deletes. The header toggles between notes and archive.
    private var notesSidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader(activeTitle: "Notes", showsArchive: $viewModel.notesSidebarShowsArchive)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.notesSidebarShowsArchive {
                        if notesStore.archivedNotes.isEmpty {
                            sidebarEmpty("Nothing archived")
                        }
                        ForEach(notesStore.archivedNotes) { note in
                            noteRow(note, archived: true)
                        }
                    } else {
                        ForEach(notesStore.activeNotes) { note in
                            noteRow(note, archived: false)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 450)
        }
        .frame(width: 220)
    }

    private func noteRow(_ note: Note, archived: Bool) -> some View {
        Button {
            guard !archived else { return }
            viewModel.openNote(note.id)
        } label: {
            NoteRowView(
                note: note,
                isSelected: !archived && note.id == notesStore.currentNote?.id,
                isHovered: viewModel.hoveredID == note.id.uuidString
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if archived {
                Button("Unarchive") { viewModel.unarchiveNote(note.id) }
            } else {
                Button("Archive") { viewModel.archiveNote(note.id) }
            }
            Button("Delete", role: .destructive) { viewModel.deleteNote(note.id) }
        }
        .id(note.id)
        .onHover { hovering in
            viewModel.setHovered(note.id.uuidString, hovering: hovering)
        }
    }

    private var noteText: String {
        notesStore.currentNote?.text ?? ""
    }

    private var noteEditor: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { notesStore.currentNote?.text ?? "" },
                    set: { notesStore.updateCurrentNote(text: $0) }
                ))
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(height: 420)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if noteText.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 21)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
            }
            .padding(.top, 4)

            Divider()

            HStack(spacing: 16) {
                Text("⌘N New")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if confirmDelete {
                    Text("Delete note?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button {
                        if let id = notesStore.currentNote?.id {
                            notesStore.delete(id: id)
                        }
                        confirmDelete = false
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete the note")
                    Button {
                        confirmDelete = false
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Keep the note")
                } else {
                    Button {
                        viewModel.createNote()
                    } label: {
                        Image(systemName: "plus.square")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New note (⌘N)")

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(noteText, forType: .string)
                        showsCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            showsCopied = false
                        }
                    } label: {
                        Image(systemName: showsCopied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(noteText.isEmpty)
                    .help(showsCopied ? "Copied" : "Copy to clipboard")
                    .opacity(noteText.isEmpty ? 0.4 : 1)

                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(noteText.isEmpty)
                    .help("Delete note")
                    .opacity(noteText.isEmpty ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var aiChatTool: some View {
        Group {
            if chatHasKey {
                HStack(alignment: .top, spacing: 0) {
                    chatSidebar
                    Divider()
                    VStack(spacing: 0) {
                        chatHeader
                        Divider()
                        chatMessages
                        if let chatError = viewModel.chatError {
                            Divider()
                            Text(chatError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        chatInputRow
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("AI Chat")
                        .font(.system(size: 14, weight: .medium))
                    Text("Add your provider and API key in Settings → AI Chat to start chatting.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { chatHasKey = APIKeyStore.read() != nil }
        .onChange(of: viewModel.focusToken) { _ in
            // Settings may have changed while the panel was closed.
            chatHasKey = APIKeyStore.read() != nil
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Text(chatStore.currentDiscussion?.title ?? "New chat")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !chatStore.currentMessages.isEmpty {
                Button {
                    copyTranscript()
                } label: {
                    Image(systemName: chatCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help(chatCopied ? "Copied" : "Copy the whole discussion")
            }

            Button {
                viewModel.createNewChatDiscussion()
                viewModel.chatError = nil
            } label: {
                Image(systemName: "plus.square")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .help("New discussion (⌘N)")

            Button {
                viewModel.chatExpanded.toggle()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.chatExpanded ? "Compact view" : "Expand for longer conversations")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The persistent discussions sidebar — the old Cmd+P history list, now
    /// always visible beside the conversation. Click a row to open it;
    /// right-click archives or deletes. The header toggles between chats
    /// and archive.
    private var chatSidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader(activeTitle: "Chats", showsArchive: $viewModel.chatsSidebarShowsArchive)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.chatsSidebarShowsArchive {
                        if chatStore.archivedDiscussions.isEmpty {
                            sidebarEmpty("Nothing archived")
                        }
                        ForEach(chatStore.archivedDiscussions) { discussion in
                            discussionRow(discussion, archived: true)
                        }
                    } else {
                        if chatStore.activeDiscussions.isEmpty {
                            sidebarEmpty("No discussions yet")
                        }
                        ForEach(chatStore.activeDiscussions) { discussion in
                            discussionRow(discussion, archived: false)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 450)
        }
        .frame(width: 220)
    }

    private func discussionRow(_ discussion: ChatDiscussion, archived: Bool) -> some View {
        Button {
            guard !archived else { return }
            viewModel.openSelectedDiscussionID(discussion.id)
        } label: {
            ChatDiscussionRowView(
                discussion: discussion,
                isSelected: !archived && discussion.id == chatStore.currentDiscussion?.id,
                isHovered: viewModel.hoveredID == discussion.id.uuidString
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if archived {
                Button("Unarchive") { viewModel.unarchiveDiscussion(discussion.id) }
            } else {
                Button("Archive") { viewModel.archiveDiscussion(discussion.id) }
            }
            Button("Delete", role: .destructive) { viewModel.deleteDiscussionByID(discussion.id) }
        }
        .id(discussion.id)
        .onHover { hovering in
            viewModel.setHovered(discussion.id.uuidString, hovering: hovering)
        }
    }

    /// The Notes/Chats | Archive segmented toggle at the top of a tool
    /// sidebar.
    private func sidebarHeader(activeTitle: String, showsArchive: Binding<Bool>) -> some View {
        HStack(spacing: 4) {
            sidebarHeaderTab(activeTitle, selected: !showsArchive.wrappedValue) {
                showsArchive.wrappedValue = false
            }
            sidebarHeaderTab("Archive", selected: showsArchive.wrappedValue) {
                showsArchive.wrappedValue = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func sidebarHeaderTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func sidebarEmpty(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(16)
    }

    private func copyTranscript() {
        let transcript = chatStore.currentMessages
            .map { ($0.role == .user ? "You: " : "AI: ") + $0.text }
            .joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        chatCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            chatCopied = false
        }
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(chatStore.currentMessages.enumerated()), id: \.offset) { index, message in
                        ChatBubbleView(message: message)
                            .id(index)
                    }
                    if viewModel.chatSending {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // Fixed at the normal size when compact (an empty chat keeps the
            // panel launcher-sized instead of collapsing), ~80% of the
            // viewport when expanded.
            .frame(minHeight: 380, maxHeight: viewModel.chatExpanded ? 10000 : 380)
            .onChange(of: chatStore.discussions) { _ in
                scrollToBottom(proxy)
            }
            .onAppear {
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if viewModel.chatSending {
            proxy.scrollTo("thinking", anchor: .bottom)
        } else {
            proxy.scrollTo(max(chatStore.currentMessages.count - 1, 0), anchor: .bottom)
        }
    }

    /// The expanded Quick AI panel height: ~80% of the viewport, measured on
    /// the screen the launcher opened on.
    private var chatExpandedHeight: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return visible.height * 0.8
    }

    private var chatInputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Vertical axis: the draft grows with Shift+Return newlines
            // (and wrapping), up to six lines before it starts scrolling.
            TextField("Message…", text: $viewModel.chatInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...6)
                .focused($chatFocused)
            Button {
                viewModel.sendChatMessage()
            } label: {
                if viewModel.chatSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperplane")
                        .foregroundStyle(viewModel.chatInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 3)
            .disabled(viewModel.chatSending || viewModel.chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Send (Return)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transformerTool: some View {
        VStack(spacing: 0) {
            switch viewModel.transformerState {
            case .capturing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading selection…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(24)

            case .noSelection:
                VStack(spacing: 6) {
                    Image(systemName: "textformat")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("Nothing selected")
                        .font(.system(size: 14, weight: .medium))
                    Text("Select text in any app, then open Text Transformer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)

            case .ready:
                if viewModel.transforms.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "textformat")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                        Text("No transformations enabled")
                            .font(.system(size: 14, weight: .medium))
                        Text("Enable them in Settings → Text Transformer")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected text")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(singleLinePreview(viewModel.transformerText))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.transforms.enumerated()), id: \.element.id) { index, transform in
                                    TransformRowView(
                                        transform: transform,
                                        preview: singleLinePreview(transform.apply(to: viewModel.transformerText)),
                                        isSelected: index == viewModel.transformSelectedIndex,
                                        isHovered: viewModel.hoveredID == transform.id
                                    )
                                    .id(transform.id)
                                    .onHover { hovering in
                                        viewModel.setHovered(transform.id, hovering: hovering)
                                    }
                                    .onTapGesture {
                                        LauncherController.shared.applySelectedTransform()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 360)
                        .onChange(of: viewModel.transformSelectedIndex) { index in
                            if let transform = viewModel.transforms[safe: index] {
                                proxy.scrollTo(transform.id, anchor: .center)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("Return replaces the selection")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    /// A one-line preview of (possibly multiline) text for transformer rows.
    private func singleLinePreview(_ text: String) -> String {
        let flattened = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flattened.prefix(120))
    }

    private var selectedID: String? {
        viewModel.filtered[safe: viewModel.selectedIndex]?.id
    }

    /// The ⌘K hint shows whenever a result row can have options — search
    /// results, category lists, and the recents view, but not the actions
    /// view or the scratchpad editor.
    private var showsOptionsFooter: Bool {
        viewModel.selectedCategory != .scratchpad
            && !viewModel.filtered.isEmpty
    }

    private var shouldShowSectionHeader: Bool {
        viewModel.selectedCategory == .all && viewModel.sections.count > 1
    }
}

extension AnyTransition {
    /// The tool-category switch: a plain opacity crossfade — the native
    /// macOS pattern for switching content panes. Deliberately no blur (a
    /// live CI filter per frame stutters), no scale (the panel resize is
    /// the one motion). 0.2s matches the panel's NSAnimationContext resize,
    /// NSAnimationContext's own default duration.
    static var toolSwitch: AnyTransition {
        .opacity
    }
}

extension Date {
    /// "Oct 3" for the current year, "Oct 3, 2025" otherwise — the plain
    /// date for list rows, instead of relative "2 hours ago" text.
    var rowDateLabel: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.component(.year, from: self) == calendar.component(.year, from: Date()) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        }
        return formatter.string(from: self)
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage

    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                messageContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.role == .user
                                  ? Color.accentColor.opacity(0.25)
                                  : Color.secondary.opacity(0.12))
                    )
                if message.role == .assistant, isHovered {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(message.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(copied ? "Copied" : "Copy reply")
                }
            }
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .onHover { isHovered = $0 }
    }

    /// Assistant replies render as parsed markdown blocks (headings, lists,
    /// code fences, quotes, inline styling); user messages stay verbatim.
    @ViewBuilder private var messageContent: some View {
        if message.role == .assistant {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ChatMarkdown.blocks(from: message.text).enumerated()), id: \.offset) { _, block in
                    ChatMarkdownBlock(block: block)
                }
            }
            .font(.system(size: 13))
            .lineLimit(nil)
            .textSelection(.enabled)
        } else {
            Text(message.text)
                .font(.system(size: 13))
                .lineLimit(nil)
        }
    }
}

struct ChatDiscussionRowView: View {
    let discussion: ChatDiscussion
    let isSelected: Bool
    var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(discussion.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(discussion.updatedAt.rowDateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if isHovered { return Color.accentColor.opacity(0.10) }
        return Color.clear
    }
}

struct TransformRowView: View {
    let transform: TextTransform
    let preview: String
    let isSelected: Bool
    var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
            Text(transform.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Text(preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if isHovered { return Color.accentColor.opacity(0.10) }
        return Color.clear
    }
}

struct NoteRowView: View {
    let note: Note
    let isSelected: Bool
    var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.excerpt.isEmpty ? "Empty note" : note.excerpt)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(note.updatedAt.rowDateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if isHovered { return Color.accentColor.opacity(0.10) }
        return Color.clear
    }
}

struct LauncherRowView: View {
    // The row observes the view model itself and derives isSelected/isHovered
    // from it: rows that moved between sections (favorites -> search results)
    // get reused by the LazyVStack under the same ForEach id, and a reused
    // row silently stops painting INPUT-driven changes on this macOS version.
    // A view that self-invalidates on every model change can't go stale.
    @ObservedObject var viewModel: LauncherViewModel
    let item: LauncherItem
    var canFavorite = false

    private var isSelected: Bool {
        viewModel.filtered[safe: viewModel.selectedIndex]?.id == item.id
    }

    private var isHovered: Bool {
        viewModel.hoveredID == item.id
    }

    // Derived, not passed in: reused rows keep stale INPUT values when body
    // re-runs, so a row created during a search kept underlining the old
    // query's matches after the search was cleared.
    private var query: String {
        viewModel.query
    }

    private var isFavorite: Bool {
        viewModel.isFavorite(item)
    }

    private var hotkeyDisplay: String? {
        viewModel.hotkeyDisplay(for: item)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let nsImage = item.iconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: item.icon)
                    .foregroundStyle(iconForeground)
                    .frame(width: 22, height: 22)
            }
            highlightedTitle
                .font(toolNumber != nil ? .system(size: 13, weight: .medium) : .body)
                .lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let toolNumber {
                // Tools render compact in the recents view, with the same
                // ⌘-number badge the actions grid uses.
                HStack(spacing: 2) {
                    Image(systemName: "command")
                        .font(.system(size: 7, weight: .bold))
                    Text("\(toolNumber)")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let hotkeyDisplay {
                Text(hotkeyDisplay)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, toolNumber != nil ? 6 : 9)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
        .contextMenu {
            if canFavorite {
                Button("Options…") {
                    viewModel.openOptions(for: item.id)
                }
            }
            if case .colorEntry(let color) = item {
                Button("Copy Hex") {
                    copyColorText(color.hex)
                }
                Button("Copy RGB") {
                    copyColorText(color.rgbText)
                }
                Button("Copy HSL") {
                    copyColorText(color.hslText)
                }
                Divider()
                Button("Remove Color", role: .destructive) {
                    ColorStore.shared.remove(color)
                    LauncherController.shared.refreshItems()
                }
            }
        }
    }

    /// Context-menu copies keep the panel open — Return is the copy-and-
    /// close path (hex); the menu is the quick multi-format affordance.
    private func copyColorText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// The actions-grid number for tool rows in the recents view.
    private var toolNumber: Int? {
        if case .toolEntry(_, let number) = item { return number }
        return nil
    }

    /// Row icon color: everything stays muted; the only amber accent in the
    /// app is the search-bar logo.
    private var iconForeground: Color {
        .secondary
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if isHovered { return Color.accentColor.opacity(0.10) }
        return Color.clear
    }

    private var highlightedTitle: Text {
        let title = item.title.isEmpty ? "Untitled" : item.title
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty,
              let indices = FuzzyMatch.matchedIndices(query: trimmedQuery, target: title),
              !indices.isEmpty else {
            return Text(title)
        }

        // Build matched/unmatched runs instead of one AttributedString per
        // character — the per-character version allocated a string per glyph
        // per row on every keystroke.
        let matchedSet = Set(indices)
        var result = AttributedString()
        var run = ""
        var runIsMatched = matchedSet.contains(0)

        func flushRun() {
            guard !run.isEmpty else { return }
            var attributed = AttributedString(run)
            if runIsMatched {
                attributed.font = .body.weight(.bold)
                attributed.underlineStyle = Text.LineStyle(pattern: .solid)
            }
            result += attributed
            run = ""
        }

        for (offset, char) in title.enumerated() {
            let isMatched = matchedSet.contains(offset)
            if isMatched != runIsMatched {
                flushRun()
                runIsMatched = isMatched
            }
            run.append(char)
        }
        flushRun()
        return Text(result)
    }
}
