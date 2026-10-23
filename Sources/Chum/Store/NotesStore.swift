import Foundation
import Combine
import ChumCore

/// Persistent scratchpad notes (versioned JSON at
/// `~/Library/Application Support/Chum/notes.json`), ordered by most
/// recently updated. The scratchpad always has a current note — the editor
/// edits it, and the notes list (Cmd+P) switches between past ones.
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    private struct Container: Codable {
        var version: Int = 1
        var notes: [Note] = []
    }

    private static let currentNoteIDKey = "scratchpadCurrentNoteID"
    private static let migratedKey = "scratchpadNotesMigrated"
    private static let saveDelay: TimeInterval = 0.5

    @Published private(set) var notes: [Note] = []
    private var currentNoteID: UUID?
    private let fileURL: URL?
    private var saveDebounce: DispatchWorkItem?

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Chum", isDirectory: true)
        fileURL = directory?.appendingPathComponent("notes.json")
        load()
        migrateLegacyScratchpad()
        // The editor always has something to type into — deleting the last
        // note simply produces a fresh empty one.
        if notes.isEmpty {
            notes = [Note()]
            currentNoteID = notes[0].id
            save()
        }
    }

    /// The note the scratchpad editor shows; falls back to the most recently
    /// updated ACTIVE note when no explicit selection is persisted. The
    /// editor never edits an archived note.
    var currentNote: Note? {
        notes.first { $0.id == currentNoteID && !$0.isArchived }
            ?? notes.first { !$0.isArchived }
    }

    /// The active (non-archived) notes for the sidebar list.
    var activeNotes: [Note] {
        notes.filter { !$0.isArchived }
    }

    /// Archived notes for the sidebar's Archive list.
    var archivedNotes: [Note] {
        notes.filter { $0.isArchived }
    }

    /// Typing in the editor lands here once per keystroke; only the disk
    /// write is debounced, the in-memory note (and ordering) updates
    /// immediately so the view stays live.
    func updateCurrentNote(text: String) {
        guard let note = currentNote, note.text != text else { return }
        update(note.id, text: text)
    }

    /// Creates an empty note, makes it current, and returns its id.
    @discardableResult
    func createNote() -> UUID {
        let note = Note()
        notes.insert(note, at: 0)
        currentNoteID = note.id
        persistCurrentNote()
        save()
        return note.id
    }

    /// Opens a note from the sidebar in the editor.
    func open(id: UUID) {
        guard notes.contains(where: { $0.id == id && !$0.isArchived }) else { return }
        currentNoteID = id
        persistCurrentNote()
    }

    /// Archives a note; if it was current, the editor falls back to the most
    /// recently updated remaining active note — and archiving the last one
    /// produces a fresh empty note, so the editor always has a current note.
    func archive(id: UUID) {
        setArchived(true, id: id)
    }

    func unarchive(id: UUID) {
        setArchived(false, id: id)
    }

    private func setArchived(_ archived: Bool, id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isArchived = archived
        if archived, currentNoteID == id {
            currentNoteID = nil
        }
        if archived, activeNotes.isEmpty {
            let note = Note()
            notes.insert(note, at: 0)
            currentNoteID = note.id
        }
        persistCurrentNote()
        save()
    }

    /// Deletes a note; if it was current, the editor falls back to the most
    /// recently updated remaining active note. Deleting the last active one
    /// produces a fresh empty note (archived notes never become current).
    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        if currentNoteID == id { currentNoteID = nil }
        if activeNotes.isEmpty {
            notes.insert(Note(), at: 0)
            currentNoteID = notes[0].id
        }
        persistCurrentNote()
        save()
    }

    /// The Settings "delete all" — one fresh empty note remains.
    func deleteAll() {
        notes = [Note()]
        currentNoteID = notes[0].id
        persistCurrentNote()
        save()
    }

    // MARK: - Private

    private func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        saveDebounced()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        if let container = try? JSONDecoder().decode(Container.self, from: data) {
            notes = container.notes.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let idString = UserDefaults.standard.string(forKey: Self.currentNoteIDKey),
           let id = UUID(uuidString: idString) {
            currentNoteID = id
        }
    }

    /// The old scratchpad was one text blob in UserDefaults; it becomes the
    /// first note, once.
    private func migrateLegacyScratchpad() {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)
        let legacy = UserDefaults.standard.string(forKey: AppSettings.scratchpadTextKey) ?? ""
        guard !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = Note(text: legacy)
        notes.insert(note, at: 0)
        currentNoteID = note.id
        save()
    }

    private func persistCurrentNote() {
        UserDefaults.standard.set(currentNoteID?.uuidString, forKey: Self.currentNoteIDKey)
    }

    private func saveDebounced() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func save() {
        guard let fileURL else { return }
        let container = Container(notes: notes)
        guard let data = try? JSONEncoder().encode(container) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
