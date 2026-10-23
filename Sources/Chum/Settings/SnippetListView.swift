import SwiftUI
import ChumCore

struct SnippetListView: View {
    @EnvironmentObject private var store: SnippetStore
    @State private var selectionID: UUID?

    var body: some View {
        HSplitView {
            List(selection: $selectionID) {
                let enabled = store.snippets.filter { $0.enabled }
                let disabled = store.snippets.filter { !$0.enabled }

                if !enabled.isEmpty {
                    Section("Enabled") {
                        ForEach(enabled) { snippet in
                            row(for: snippet)
                        }
                    }
                }
                if !disabled.isEmpty {
                    Section("Disabled") {
                        ForEach(disabled) { snippet in
                            row(for: snippet)
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
                    SnippetEditorView(snippet: binding) {
                        store.remove(binding.wrappedValue)
                        self.selectionID = nil
                    }
                } else {
                    Text("Select a snippet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let snippet = store.add(Snippet())
                        selectionID = snippet.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add snippet")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        duplicateSelection()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(selectionID == nil)
                    .help("Duplicate snippet")
                }
            }
        }
    }

    private func row(for snippet: Snippet) -> some View {
        HStack {
            Image(systemName: snippet.enabled ? "text.append" : "text.append.slash")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name.isEmpty ? "Untitled" : snippet.name)
                    .lineLimit(1)
                if !snippet.keyword.isEmpty {
                    Text(snippet.keyword)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private func duplicateSelection() {
        guard let selectionID, let snippet = store.snippet(withID: selectionID) else { return }
        self.selectionID = store.duplicate(snippet).id
    }
}

struct SnippetEditorView: View {
    @Binding var snippet: Snippet
    var onDelete: (() -> Void)?

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Snippet") {
                TextField("Name", text: $snippet.name)
                TextField("Keyword", text: $snippet.keyword)
                    .autocorrectionDisabled()
                Toggle("Enabled", isOn: $snippet.enabled)
            }

            Section {
                TextEditor(text: $snippet.content)
                    .font(.system(size: 13))
                    .frame(minHeight: 120)
            } header: {
                Text("Content")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type the keyword anywhere on the system to expand it into the content text.")
                    Text("Template variables:")
                    Text("  {{clipboard}} — current clipboard text")
                    Text("  {{date}} — today (yyyy-MM-dd)")
                    Text("  {{date -1}} — yesterday, {{date +7}} — next week")
                    Text("  {{date:MMMM d, yyyy}} — custom date format")
                    Text("  {{time}} — current time (HH:mm:ss)")
                }
                .font(.caption)
            }

            Section {
                Button("Test Expansion") {
                    let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
                    let resolved = SnippetTemplate.resolve(snippet.content, clipboardContent: clipboard)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resolved, forType: .string)
                }
                .disabled(!snippet.isValid)
            } header: {
                Text("Test")
            } footer: {
                Text("Copies the expansion text to the clipboard — paste it with Cmd+V to verify.")
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Snippet…")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete \"\(snippet.name)\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This snippet will be removed. This cannot be undone.")
        }
    }
}
