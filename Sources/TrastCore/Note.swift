import Foundation

/// A persistent scratchpad note. The scratchpad is deliberately not a notes
/// app — the model carries text and timestamps only, and list UI shows just
/// `excerpt`, a single line of the note.
public struct Note: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Archived notes leave the active sidebar list; the launcher's sidebar
    /// Archive toggle lists them.
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    /// One-line excerpt for list rows: the first non-empty line, whitespace
    /// collapsed, capped at 80 characters so rows stay single-line.
    public var excerpt: String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let collapsed = trimmed.split(separator: " ").joined(separator: " ")
            return String(collapsed.prefix(80))
        }
        return ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, updatedAt, isArchived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isArchived, forKey: .isArchived)
    }
}
