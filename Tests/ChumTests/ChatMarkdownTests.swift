import ChumCore
import Foundation

enum ChatMarkdownTests {
    static func runAll(_ t: TestRunner) {
        t.run("ChatMarkdown.paragraphsJoinAndSplit") {
            let blocks = ChatMarkdown.blocks(from: "first line\nwraps here\n\nsecond paragraph")
            t.check(blocks.count == 2, "two blocks, got \(blocks.count)")
            t.check(blocks[0] == .paragraph("first line wraps here"), "soft-wrapped lines joined, got \(blocks[0])")
            t.check(blocks[1] == .paragraph("second paragraph"), "blank line separates")
        }

        t.run("ChatMarkdown.headings") {
            let blocks = ChatMarkdown.blocks(from: "# Title\n\n### Section\n\nNormal text")
            t.check(blocks[0] == .heading(level: 1, text: "Title"), "h1, got \(blocks[0])")
            t.check(blocks[1] == .heading(level: 3, text: "Section"), "h3, got \(blocks[1])")
            t.check(blocks[2] == .paragraph("Normal text"), "text after headings")
            t.check(ChatMarkdown.blocks(from: "#nospace") == [.paragraph("#nospace")], "missing space is not a heading")
        }

        t.run("ChatMarkdown.lists") {
            let blocks = ChatMarkdown.blocks(from: "- one\n- two\n  continued\n- three\n\n1. first\n2. second\n\nplain")
            t.check(blocks[0] == .bulletList(["one", "two continued", "three"]), "bullets with lazy continuation, got \(blocks[0])")
            t.check(blocks[1] == .orderedList(["first", "second"]), "ordered list, got \(blocks[1])")
            t.check(blocks[2] == .paragraph("plain"), "trailing paragraph")
            t.check(ChatMarkdown.blocks(from: "-5 degrees outside") == [.paragraph("-5 degrees outside")], "minus sign is not a bullet")
        }

        t.run("ChatMarkdown.codeFence") {
            let input = "before\n```swift\nlet x = 1\nlet y = 2\n```\nafter"
            let blocks = ChatMarkdown.blocks(from: input)
            t.check(blocks.count == 3, "three blocks, got \(blocks.count)")
            t.check(blocks[0] == .paragraph("before"), "leading paragraph")
            t.check(blocks[1] == .codeBlock(language: "swift", code: "let x = 1\nlet y = 2"), "fence with language, got \(blocks[1])")
            t.check(blocks[2] == .paragraph("after"), "trailing paragraph")
        }

        t.run("ChatMarkdown.unclosedFenceRunsToEOF") {
            let blocks = ChatMarkdown.blocks(from: "```\nplain code\nmore code")
            t.check(blocks == [.codeBlock(language: nil, code: "plain code\nmore code")], "no closing fence, got \(blocks)")
        }

        t.run("ChatMarkdown.blockQuote") {
            let blocks = ChatMarkdown.blocks(from: "> quoted line\n> more\n\nreply")
            t.check(blocks[0] == .blockQuote("quoted line more"), "quote lines joined, got \(blocks[0])")
            t.check(blocks[1] == .paragraph("reply"), "paragraph after quote")
        }

        t.run("ChatMarkdown.inlineStyles") {
            func containsIntent(_ text: String, intent: InlinePresentationIntent) -> Bool {
                let attributed = ChatMarkdown.inlineAttributedString(text)
                return attributed.runs.contains { run in
                    run.inlinePresentationIntent?.contains(intent) == true
                }
            }

            t.check(containsIntent("**bold** text", intent: .stronglyEmphasized), "bold run found")
            t.check(containsIntent("*italic*", intent: .emphasized), "italic run found")
            t.check(containsIntent("use `foo()` here", intent: .code), "inline code run found")

            let plain = ChatMarkdown.inlineAttributedString("just words")
            t.check(String(plain.characters) == "just words", "plain text unchanged")
        }

        t.run("ChatMarkdown.tableParsing") {
            let input = """
            intro line

            | Camera | Price | Pros |
            |--------|:-----:|-----:|
            | Sony ZV-E1 | ~€800 | Full-frame |
            | Canon R50 | ~€600 | Dual Pixel AF |
            | extra | cells | that | overflow |

            after
            """
            let blocks = ChatMarkdown.blocks(from: input)
            t.check(blocks.count == 3, "three blocks, got \(blocks.count)")
            guard case .table(let header, let aligns, let rows)? = blocks[safe: 1] else {
                t.check(false, "block 1 is not a table, got \(blocks[safe: 1])")
                return
            }
            t.check(header == ["Camera", "Price", "Pros"], "header cells, got \(header)")
            t.check(aligns == [.leading, .center, .trailing], "delimiter alignment, got \(aligns)")
            t.check(rows.count == 3, "three body rows, got \(rows.count)")
            t.check(rows[0] == ["Sony ZV-E1", "~€800", "Full-frame"], "first row, got \(rows[0])")
            t.check(rows[2] == ["extra", "cells", "that"], "wide rows truncated to header width, got \(rows[2])")
            t.check(blocks[2] == .paragraph("after"), "paragraph after table")
        }

        t.run("ChatMarkdown.tableEdgeCases") {
            // A stray pipe line with no delimiter after it is a paragraph.
            t.check(
                ChatMarkdown.blocks(from: "a | b\nc") == [.paragraph("a | b c")],
                "pipe without delimiter row stays a paragraph"
            )
            // Escaped pipes are literal content, not cell separators.
            let escaped = ChatMarkdown.blocks(from: "| a \\| b | c |\n|---|---|\n| 1 | 2 |")
            guard case .table(let header, _, _)? = escaped.first else {
                t.check(false, "escaped table did not parse, got \(escaped)")
                return
            }
            t.check(header == ["a | b", "c"], "escaped pipe kept in cell, got \(header)")
            // Rows without outer pipes parse too.
            let noPipes = ChatMarkdown.blocks(from: "a | b\n--- | ---\n1 | 2")
            guard case .table(let header2, _, let rows2)? = noPipes.first else {
                t.check(false, "bare table did not parse, got \(noPipes)")
                return
            }
            t.check(header2 == ["a", "b"], "bare header, got \(header2)")
            t.check(rows2 == [["1", "2"]], "bare rows, got \(rows2)")
        }

        t.run("ChatMarkdown.emptyInput") {
            t.check(ChatMarkdown.blocks(from: "") == [], "empty")
            t.check(ChatMarkdown.blocks(from: "\n\n  \n") == [], "blank lines only")
        }
    }
}
