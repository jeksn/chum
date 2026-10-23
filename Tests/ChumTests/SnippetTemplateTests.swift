import Foundation
import ChumCore

enum SnippetTemplateTests {
    static func runAll(_ t: TestRunner) {
        t.run("SnippetTemplate.plainText") {
            let result = SnippetTemplate.resolve("Hello world")
            t.check(result == "Hello world", "plain text should pass through")
        }

        t.run("SnippetTemplate.clipboard") {
            let result = SnippetTemplate.resolve("Paste: {{clipboard}}", clipboardContent: "copied text")
            t.check(result == "Paste: copied text", "got \(result)")
        }

        t.run("SnippetTemplate.clipboardEmpty") {
            let result = SnippetTemplate.resolve("Paste: {{clipboard}}", clipboardContent: "")
            t.check(result == "Paste: ", "got \(result)")
        }

        t.run("SnippetTemplate.date") {
            let result = SnippetTemplate.resolve("{{date}}")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let expected = formatter.string(from: Date())
            t.check(result == expected, "got \(result), expected \(expected)")
        }

        t.run("SnippetTemplate.dateWithOffset") {
            let result = SnippetTemplate.resolve("{{date -1}}")
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let expected = formatter.string(from: yesterday)
            t.check(result == expected, "got \(result), expected \(expected)")
        }

        t.run("SnippetTemplate.datePositiveOffset") {
            let result = SnippetTemplate.resolve("{{date +7}}")
            let calendar = Calendar.current
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let expected = formatter.string(from: nextWeek)
            t.check(result == expected, "got \(result), expected \(expected)")
        }

        t.run("SnippetTemplate.dateWithCustomFormat") {
            let result = SnippetTemplate.resolve("{{date:MMMM d, yyyy}}")
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            let expected = formatter.string(from: Date())
            t.check(result == expected, "got \(result), expected \(expected)")
        }

        t.run("SnippetTemplate.dateWithOffsetAndFormat") {
            let result = SnippetTemplate.resolve("{{date -1:yyyy/MM/dd}}")
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd"
            let expected = formatter.string(from: yesterday)
            t.check(result == expected, "got \(result), expected \(expected)")
        }

        t.run("SnippetTemplate.time") {
            let result = SnippetTemplate.resolve("{{time}}")
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let expected = formatter.string(from: Date())
            t.check(result == expected, "got \(result), expected \(expected)")
        }

        t.run("SnippetTemplate.multipleVariables") {
            let result = SnippetTemplate.resolve("Date: {{date}}\nTime: {{time}}\nClip: {{clipboard}}", clipboardContent: "test")
            t.check(result.contains("Date: "), "should contain date label")
            t.check(result.contains("Time: "), "should contain time label")
            t.check(result.contains("Clip: test"), "should contain clipboard value")
        }

        t.run("SnippetTemplate.noMatchLeftAsIs") {
            let result = SnippetTemplate.resolve("Hello {{unknown}} world")
            t.check(result == "Hello {{unknown}} world", "unknown variables should pass through")
        }

        t.run("SnippetTemplate.multipleDates") {
            let result = SnippetTemplate.resolve("From {{date -2}} to {{date +2}}")
            let calendar = Calendar.current
            let past = calendar.date(byAdding: .day, value: -2, to: Date())!
            let future = calendar.date(byAdding: .day, value: 2, to: Date())!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let expected = "From \(formatter.string(from: past)) to \(formatter.string(from: future))"
            t.check(result == expected, "got \(result), expected \(expected)")
        }
    }
}
