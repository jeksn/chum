import Foundation
import ChumCore

enum SnippetTextEditTests {
    static func runAll(_ t: TestRunner) {
        t.run("SnippetTextEdit.caretAtEnd") {
            // "say !zsh" with caret at the end, empty selection.
            let range = SnippetTextEdit.replacementRange(
                value: "say !zsh", selectionStart: 8, selectionLength: 0, keyword: "!zsh")
            t.check(range == NSRange(location: 4, length: 4), "range is the keyword at the caret")
        }

        t.run("SnippetTextEdit.midText") {
            // Keyword typed mid-text: caret right after it, more text follows.
            let range = SnippetTextEdit.replacementRange(
                value: "!zsh and more", selectionStart: 4, selectionLength: 0, keyword: "!zsh")
            t.check(range == NSRange(location: 0, length: 4), "range is the keyword before the caret")
        }

        t.run("SnippetTextEdit.omniboxSuggestion") {
            // Omnibox: typed "!in", the suggestion "https://example.com" (19 chars) is the selection.
            let range = SnippetTextEdit.replacementRange(
                value: "!inhttps://example.com", selectionStart: 3, selectionLength: 19, keyword: "!in")
            t.check(range == NSRange(location: 0, length: 3 + 19),
                    "range covers keyword plus the selected suggestion")
        }

        t.run("SnippetTextEdit.keywordNotAtCaret") {
            let range = SnippetTextEdit.replacementRange(
                value: "!zsh", selectionStart: 0, selectionLength: 0, keyword: "!zsh")
            t.check(range == nil, "no caret after the keyword means no match")
        }

        t.run("SnippetTextEdit.keywordMismatch") {
            let range = SnippetTextEdit.replacementRange(
                value: "say !zsx", selectionStart: 8, selectionLength: 0, keyword: "!zsh")
            t.check(range == nil, "value not ending in the keyword means no match")
        }

        t.run("SnippetTextEdit.emptyKeyword") {
            let range = SnippetTextEdit.replacementRange(
                value: "abc", selectionStart: 3, selectionLength: 0, keyword: "")
            t.check(range == nil, "empty keyword never matches")
        }

        t.run("SnippetTextEdit.unicodeOffsets") {
            // Emoji are multi-UTF-16-unit; offsets must be UTF-16, not Character counts.
            let value = "hi 👋 !zsh"
            let caret = (value as NSString).length
            let range = SnippetTextEdit.replacementRange(
                value: value, selectionStart: caret, selectionLength: 0, keyword: "!zsh")
            t.check(range == NSRange(location: caret - 4, length: 4),
                    "range uses UTF-16 offsets past the emoji")
            let replaced = SnippetTextEdit.replacedValue(value: value, range: range!, expansion: "x")
            t.check(replaced == "hi 👋 x", "replacement lands at the right spot, got \(replaced)")
        }

        t.run("SnippetTextEdit.caretAfterExpansion") {
            let caret = SnippetTextEdit.caretAfterExpansion(in: NSRange(location: 4, length: 4), expansion: "hello")
            t.check(caret == 9, "caret lands right after the expansion")
        }

        t.run("SnippetTextEdit.isAppliedExact") {
            let ok = SnippetTextEdit.isApplied(current: "say hello", expected: "say hello",
                                               insertLocation: 4, expansion: "hello")
            t.check(ok, "exact value matches")
        }

        t.run("SnippetTextEdit.isAppliedNormalized") {
            // App appended a trailing newline after the set.
            let ok = SnippetTextEdit.isApplied(current: "say hello\n", expected: "say hello",
                                               insertLocation: 4, expansion: "hello")
            t.check(ok, "expansion at the insert location counts as applied")
        }

        t.run("SnippetTextEdit.isAppliedIgnored") {
            // Read-only element: set reported success but the value is unchanged.
            let ok = SnippetTextEdit.isApplied(current: "say !zsh", expected: "say hello",
                                               insertLocation: 4, expansion: "hello")
            t.check(!ok, "unchanged value means the set was ignored")
        }
    }
}
