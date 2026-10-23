import Foundation

public struct Snippet: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var keyword: String
    public var content: String
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        keyword: String = "",
        content: String = "",
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.content = content
        self.enabled = enabled
    }

    public var isValid: Bool {
        !name.isEmpty && !keyword.isEmpty && !content.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, keyword, content, enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(keyword, forKey: .keyword)
        try container.encode(content, forKey: .content)
        try container.encode(enabled, forKey: .enabled)
    }
}
