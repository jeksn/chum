import Foundation

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case text
        case image
        case fileURL
    }

    var id: UUID
    var kind: Kind
    var textContent: String?
    var imageData: Data?
    var fileURLString: String?
    var pinned: Bool
    var timestamp: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        textContent: String? = nil,
        imageData: Data? = nil,
        fileURLString: String? = nil,
        pinned: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.textContent = textContent
        self.imageData = imageData
        self.fileURLString = fileURLString
        self.pinned = pinned
        self.timestamp = timestamp
    }

    var fileURL: URL? {
        fileURLString.flatMap { URL(string: $0) }
    }

    var displayName: String {
        switch kind {
        case .text:
            let text = textContent ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "(empty)" }
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
            return firstLine
        case .image:
            return "Image"
        case .fileURL:
            return fileURL?.lastPathComponent ?? "File"
        }
    }

    var preview: String {
        switch kind {
        case .text:
            return textContent ?? ""
        case .image:
            return "\(imageData?.count ?? 0) bytes"
        case .fileURL:
            return fileURL?.path ?? fileURLString ?? ""
        }
    }
}
