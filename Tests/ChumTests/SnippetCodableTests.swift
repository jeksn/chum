import Foundation
import ChumCore

enum SnippetCodableTests {
    static func runAll(_ t: TestRunner) {
        t.run("Snippet.roundTrip") {
            let snippet = Snippet(
                name: "Email",
                keyword: "!mail",
                content: "user@example.com",
                enabled: true
            )
            let data = try JSONEncoder().encode(snippet)
            let decoded = try JSONDecoder().decode(Snippet.self, from: data)
            t.check(decoded == snippet, "round trip mismatch")
        }

        t.run("Snippet.disabledRoundTrip") {
            let snippet = Snippet(
                name: "Sig",
                keyword: "!sig",
                content: "Best regards",
                enabled: false
            )
            let data = try JSONEncoder().encode(snippet)
            let decoded = try JSONDecoder().decode(Snippet.self, from: data)
            t.check(decoded == snippet, "round trip mismatch")
            t.check(!decoded.enabled, "enabled should be false")
        }

        t.run("Snippet.defaults") {
            let snippet = Snippet()
            t.check(snippet.name.isEmpty, "name should default to empty")
            t.check(snippet.keyword.isEmpty, "keyword should default to empty")
            t.check(snippet.content.isEmpty, "content should default to empty")
            t.check(snippet.enabled, "enabled should default to true")
            t.check(!snippet.isValid, "empty snippet should be invalid")
        }

        t.run("Snippet.validity") {
            let valid = Snippet(name: "A", keyword: "!a", content: "text")
            t.check(valid.isValid, "non-empty fields should be valid")

            let noName = Snippet(name: "", keyword: "!a", content: "text")
            t.check(!noName.isValid, "empty name should be invalid")

            let noKeyword = Snippet(name: "A", keyword: "", content: "text")
            t.check(!noKeyword.isValid, "empty keyword should be invalid")

            let noContent = Snippet(name: "A", keyword: "!a", content: "")
            t.check(!noContent.isValid, "empty content should be invalid")
        }

        t.run("Snippet.encodingShape") {
            let snippet = Snippet(
                name: "Greeting",
                keyword: "!hi",
                content: "Hello!",
                enabled: true
            )
            let data = try JSONEncoder().encode(snippet)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            t.check(json?["name"] as? String == "Greeting", "name mismatch")
            t.check(json?["keyword"] as? String == "!hi", "keyword mismatch")
            t.check(json?["content"] as? String == "Hello!", "content mismatch")
            t.check(json?["enabled"] as? Bool == true, "enabled mismatch")
        }

        t.run("Snippet.decodesMissingFields") {
            let json = #"{"name": "Test"}"#
            let decoded = try JSONDecoder().decode(Snippet.self, from: Data(json.utf8))
            t.check(decoded.name == "Test", "name mismatch")
            t.check(decoded.keyword.isEmpty, "keyword should default to empty")
            t.check(decoded.content.isEmpty, "content should default to empty")
            t.check(decoded.enabled, "enabled should default to true")
        }
    }
}
