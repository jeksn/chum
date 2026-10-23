import Foundation
import Combine
import TrastCore

/// AI chat discussions (versioned JSON at
/// `~/Library/Application Support/Trast/chats.json`), ordered most recently
/// updated first. The current discussion id persists in UserDefaults so
/// reopening the tool lands where you left off.
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    private struct Container: Codable {
        var version: Int = 1
        var discussions: [ChatDiscussion] = []
    }

    private static let currentDiscussionIDKey = "chatCurrentDiscussionID"

    @Published private(set) var discussions: [ChatDiscussion] = []
    private var currentDiscussionID: UUID?
    private let fileURL: URL?
    private var saveDebounce: DispatchWorkItem?

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Trast", isDirectory: true)
        fileURL = directory?.appendingPathComponent("chats.json")
        load()
    }

    /// The open discussion; falls back to the most recently updated ACTIVE
    /// discussion — an archived discussion never auto-opens.
    var currentDiscussion: ChatDiscussion? {
        discussions.first { $0.id == currentDiscussionID && !$0.isArchived }
            ?? discussions.first { !$0.isArchived }
    }

    /// The active (non-archived) discussions for the sidebar list.
    var activeDiscussions: [ChatDiscussion] {
        discussions.filter { !$0.isArchived }
    }

    /// Archived discussions for the sidebar's Archive list.
    var archivedDiscussions: [ChatDiscussion] {
        discussions.filter { $0.isArchived }
    }

    /// The messages of the open discussion (empty for a fresh tool).
    var currentMessages: [ChatMessage] {
        currentDiscussion?.messages ?? []
    }

    /// Appends a message to the current discussion — creating one when the
    /// chat has none yet — and touches its updatedAt.
    func appendToCurrent(_ message: ChatMessage) {
        var discussion = currentDiscussion ?? ChatDiscussion()
        discussion.messages.append(message)
        discussion.updatedAt = Date()
        if let index = discussions.firstIndex(where: { $0.id == discussion.id }) {
            discussions[index] = discussion
        } else {
            discussions.insert(discussion, at: 0)
        }
        currentDiscussionID = discussion.id
        persistCurrentDiscussionID()
        save()
    }

    /// Opens a discussion from the sidebar.
    func open(id: UUID) {
        guard discussions.contains(where: { $0.id == id && !$0.isArchived }) else { return }
        currentDiscussionID = id
        persistCurrentDiscussionID()
    }

    /// Archives a discussion; if it was current, the conversation falls back
    /// to the most recently updated remaining active one.
    func archive(id: UUID) {
        setArchived(true, id: id)
    }

    func unarchive(id: UUID) {
        setArchived(false, id: id)
    }

    private func setArchived(_ archived: Bool, id: UUID) {
        guard let index = discussions.firstIndex(where: { $0.id == id }) else { return }
        discussions[index].isArchived = archived
        if archived, currentDiscussionID == id {
            currentDiscussionID = nil
        }
        persistCurrentDiscussionID()
        save()
    }

    /// Starts a fresh, empty discussion.
    func newDiscussion() {
        let discussion = ChatDiscussion()
        discussions.insert(discussion, at: 0)
        currentDiscussionID = discussion.id
        persistCurrentDiscussionID()
        save()
    }

    /// Deletes a discussion; the current one falls back to the most
    /// recently updated remaining.
    func delete(id: UUID) {
        discussions.removeAll { $0.id == id }
        if currentDiscussionID == id {
            currentDiscussionID = nil
        }
        persistCurrentDiscussionID()
        save()
    }

    func deleteAll() {
        discussions = []
        currentDiscussionID = nil
        persistCurrentDiscussionID()
        save()
    }

    // MARK: - Private

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        if let container = try? JSONDecoder().decode(Container.self, from: data) {
            discussions = container.discussions.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let idString = UserDefaults.standard.string(forKey: Self.currentDiscussionIDKey),
           let id = UUID(uuidString: idString) {
            currentDiscussionID = id
        }
    }

    private func persistCurrentDiscussionID() {
        UserDefaults.standard.set(currentDiscussionID?.uuidString, forKey: Self.currentDiscussionIDKey)
    }

    private func save() {
        saveDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func saveNow() {
        guard let fileURL else { return }
        let container = Container(discussions: discussions)
        guard let data = try? JSONEncoder().encode(container) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
