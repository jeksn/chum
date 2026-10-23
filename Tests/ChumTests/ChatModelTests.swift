import ChumCore
import Foundation

struct ChatModelTests {
    static func runAll(_ t: TestRunner) {
        t.run("ChatModel.codableRoundTrip") {
            let discussion = ChatDiscussion(messages: [
                ChatMessage(role: .user, text: "hello"),
                ChatMessage(role: .assistant, text: "hi there"),
            ])
            guard let data = try? JSONEncoder().encode(discussion),
                  let decoded = try? JSONDecoder().decode(ChatDiscussion.self, from: data) else {
                t.check(false, "round trip failed")
                return
            }
            t.check(decoded.messages.count == 2, "messages, got \(decoded.messages.count)")
            t.check(decoded.messages[1].text == "hi there", "assistant text")
            t.check(decoded.messages[0].role == .user, "user role")
        }

        t.run("ChatModel.defaultsForMissingFields") {
            let json = "{\"messages\": [{\"role\": \"user\"}]}"
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ChatDiscussion.self, from: data) else {
                t.check(false, "decode failed")
                return
            }
            t.check(!decoded.id.uuidString.isEmpty, "id generated")
            t.check(decoded.messages.count == 1, "one message")
            t.check(decoded.messages[0].text == "", "text defaults empty")
            t.check(decoded.messages[0].role == .user, "role")
        }

        t.run("ChatModel.title") {
            let discussion = ChatDiscussion(messages: [
                ChatMessage(role: .assistant, text: "greeting"),
                ChatMessage(role: .user, text: "  what is\n  the   capital?  "),
            ])
            t.check(discussion.title == "what is the capital?", "first user message, collapsed, got '\(discussion.title)'")
            t.check(ChatDiscussion().title == "New chat", "empty discussion")
            let long = ChatDiscussion(messages: [ChatMessage(role: .user, text: String(repeating: "x", count: 100))])
            t.check(long.title.count == 80, "capped at 80 chars")
        }

        t.run("ChatModel.isArchivedDefaultsAndRoundTrip") {
            let legacy = try JSONDecoder().decode(ChatDiscussion.self, from: Data("{\"messages\":[]}".utf8))
            t.check(legacy.isArchived == false, "missing isArchived should decode as active")
            let archived = ChatDiscussion(messages: [ChatMessage(role: .user, text: "hi")], isArchived: true)
            let decoded = try JSONDecoder().decode(ChatDiscussion.self, from: try JSONEncoder().encode(archived))
            t.check(decoded.isArchived == true, "archived flag should round-trip")
        }
    }
}
