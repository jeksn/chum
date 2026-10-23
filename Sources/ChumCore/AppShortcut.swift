import Foundation

public struct AppShortcut: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Hashable, CaseIterable, Sendable {
        case app
        case url
        case folder
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var bundleIdentifier: String?
    public var bundleURL: URL?
    public var urlString: String?
    public var folderURL: URL?
    public var showInMenuBar = false

    public init(
        id: UUID = UUID(),
        name: String = "",
        kind: Kind = .app,
        bundleIdentifier: String? = nil,
        bundleURL: URL? = nil,
        urlString: String? = nil,
        folderURL: URL? = nil,
        showInMenuBar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.urlString = urlString
        self.folderURL = folderURL
        self.showInMenuBar = showInMenuBar
    }

    public var url: URL? {
        urlString.flatMap { URL(string: $0) }
    }

    public var isValid: Bool {
        switch kind {
        case .app:
            return (bundleIdentifier != nil && !bundleIdentifier!.isEmpty)
                || (bundleURL != nil)
        case .url:
            guard let string = urlString, !string.isEmpty, URL(string: string) != nil else { return false }
            return true
        case .folder:
            return folderURL != nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case bundleIdentifier
        case bundleURL
        case urlString
        case folderURL
        case isURL
        case showInMenuBar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

        if let kindValue = try container.decodeIfPresent(Kind.self, forKey: .kind) {
            kind = kindValue
        } else {
            let isURL = try container.decodeIfPresent(Bool.self, forKey: .isURL) ?? false
            kind = isURL ? .url : .app
        }

        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        bundleURL = try container.decodeIfPresent(URL.self, forKey: .bundleURL)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        folderURL = try container.decodeIfPresent(URL.self, forKey: .folderURL)
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encodeIfPresent(bundleURL, forKey: .bundleURL)
        try container.encodeIfPresent(urlString, forKey: .urlString)
        try container.encodeIfPresent(folderURL, forKey: .folderURL)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
    }
}
