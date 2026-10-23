import ChumCore
import Foundation

enum NoteCodableTests {
    static func runAll(_ t: TestRunner) {
        t.run("Note.codableRoundTrip") {
            let note = Note(text: "hello world")
            guard let data = try? JSONEncoder().encode(note),
                  let decoded = try? JSONDecoder().decode(Note.self, from: data) else {
                t.check(false, "round trip failed")
                return
            }
            t.check(decoded.id == note.id, "id, got \(decoded.id)")
            t.check(decoded.text == "hello world", "text, got \(decoded.text)")
            t.check(decoded.createdAt == note.createdAt, "createdAt, got \(decoded.createdAt)")
            t.check(decoded.updatedAt == note.updatedAt, "updatedAt, got \(decoded.updatedAt)")
        }

        t.run("Note.defaultsForMissingFields") {
            let json = "{\"text\": \"kept\"}"
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Note.self, from: data) else {
                t.check(false, "decode failed")
                return
            }
            t.check(!decoded.id.uuidString.isEmpty, "id generated")
            t.check(decoded.text == "kept", "text, got \(decoded.text)")
            t.check(decoded.createdAt == decoded.updatedAt, "updatedAt falls back to createdAt")
        }

        t.run("Note.excerpt") {
            t.check(Note(text: "first line\nsecond line").excerpt == "first line", "first line only")
            t.check(Note(text: "  spaced   out  ").excerpt == "spaced out", "whitespace collapsed")
            t.check(Note(text: "\n\n  \nleading blanks").excerpt == "leading blanks", "skips empty lines")
            t.check(Note(text: "").excerpt == "", "empty note")
            let long = String(repeating: "a", count: 100)
            t.check(Note(text: long).excerpt.count == 80, "capped at 80 chars, got \(Note(text: long).excerpt.count)")
            t.check(Note(text: "多行\nテキスト").excerpt == "多行", "non-latin text")
        }

        t.run("Note.isArchivedDefaultsAndRoundTrip") {
            let legacy = try JSONDecoder().decode(Note.self, from: Data("{\"text\":\"old\"}".utf8))
            t.check(legacy.isArchived == false, "missing isArchived should decode as active")
            let archived = Note(text: "gone", isArchived: true)
            let decoded = try JSONDecoder().decode(Note.self, from: try JSONEncoder().encode(archived))
            t.check(decoded.isArchived == true, "archived flag should round-trip")
        }
    }
}
