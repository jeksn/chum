import Foundation
import SwiftUI
import ChumCore

final class SnippetStore: ObservableObject {
    private struct StoredSnippets: Codable {
        var version: Int
        var snippets: [Snippet]
    }

    static let shared = SnippetStore()

    @Published private(set) var snippets: [Snippet]

    private init() {
        if let loaded = Self.load() {
            snippets = loaded
        } else {
            snippets = []
            Self.save(snippets)
        }
    }

    var validSnippets: [Snippet] {
        snippets.filter { $0.isValid && $0.enabled }
    }

    func snippet(withID id: UUID) -> Snippet? {
        snippets.first { $0.id == id }
    }

    @discardableResult
    func add(_ snippet: Snippet) -> Snippet {
        var newSnippet = snippet
        newSnippet.id = UUID()
        snippets.append(newSnippet)
        save()
        return newSnippet
    }

    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    @discardableResult
    func duplicate(_ snippet: Snippet) -> Snippet {
        var copy = snippet
        copy.id = UUID()
        copy.name = uniqueName(basedOn: snippet.name)
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets.insert(copy, at: index + 1)
        } else {
            snippets.append(copy)
        }
        save()
        return copy
    }

    func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        snippets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func replace(with newSnippets: [Snippet]) {
        snippets = newSnippets
        save()
    }

    func binding(for id: UUID) -> Binding<Snippet>? {
        guard snippets.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.snippet(withID: id) ?? Snippet() },
            set: { self.update($0) }
        )
    }

    private func save() {
        Self.save(snippets)
    }

    private func uniqueName(basedOn name: String) -> String {
        var candidate = "\(name) copy"
        var counter = 2
        while snippets.contains(where: { $0.name == candidate }) {
            candidate = "\(name) copy \(counter)"
            counter += 1
        }
        return candidate
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chum", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("snippets.json")
    }

    private static func load() -> [Snippet]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredSnippets.self, from: data) else { return nil }
        return stored.snippets
    }

    private static func save(_ snippets: [Snippet]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(StoredSnippets(version: 1, snippets: snippets)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
