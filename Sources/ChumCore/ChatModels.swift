import Foundation

/// One message in an AI chat discussion.
public struct ChatMessage: Hashable, Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String
    public var createdAt: Date

    public init(role: Role, text: String, createdAt: Date = Date()) {
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case role, text, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .user
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// An AI chat discussion. The title is the excerpt of the first user
/// message — discussions stay minimal, no note-app chrome.
public struct ChatDiscussion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var messages: [ChatMessage]
    public var createdAt: Date
    public var updatedAt: Date
    /// Archived discussions leave the active sidebar list; the launcher's
    /// sidebar Archive toggle lists them.
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    /// One-line title for the history list: the first user message,
    /// whitespace-collapsed and capped.
    public var title: String {
        for message in messages where message.role == .user {
            let collapsed = message.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .joined(separator: " ")
                .split(separator: " ")
                .joined(separator: " ")
            return String(collapsed.prefix(80))
        }
        return "New chat"
    }

    private enum CodingKeys: String, CodingKey {
        case id, messages, createdAt, updatedAt, isArchived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}
