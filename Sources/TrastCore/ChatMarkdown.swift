import Foundation

/// Minimal markdown parsing for AI chat replies — the API returns raw
/// markdown and the bubble used to render it as one flat string. Block
/// structure is parsed here (pure, tested); inline styling (bold, italic,
/// code, links) is left to `AttributedString(markdown:)` via
/// `inlineAttributedString`.
public enum ChatMarkdown {
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bulletList([String])
        case orderedList([String])
        case codeBlock(language: String?, code: String)
        case blockQuote(String)
        /// GFM pipe table. Rows are padded/truncated to the header width;
        /// `aligns` carries the delimiter row's per-column alignment and
        /// may be shorter than the header (renderers default to leading).
        case table(header: [String], aligns: [ColumnAlign], rows: [[String]])
    }

    public enum ColumnAlign: String, Sendable {
        case leading
        case center
        case trailing
    }

    /// Parses a reply into display blocks: fenced code, ATX headings,
    /// bullet/ordered lists, blockquotes, and paragraphs (consecutive
    /// non-blank lines joined with spaces, per markdown soft-wrap).
    /// Intentionally not full CommonMark: no nesting, no tables, no
    /// setext headings — chat replies need readable structure, not a
    /// spec-complete renderer.
    public static func blocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []
        var quote: [String] = []
        var index = 0

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            paragraph = []
            guard !joined.isEmpty else { return }
            blocks.append(.paragraph(joined))
        }

        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bulletList(bullets)); bullets = [] }
            if !ordered.isEmpty { blocks.append(.orderedList(ordered)); ordered = [] }
        }

        func flushQuote() {
            if !quote.isEmpty {
                blocks.append(.blockQuote(quote.joined(separator: " ").trimmingCharacters(in: .whitespaces)))
                quote = []
            }
        }

        func flushAll() {
            flushParagraph()
            flushLists()
            flushQuote()
        }

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            // Fenced code block: ``` or ~~~, optional language tag, runs to
            // the closing fence or end of input.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let marker = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                        index += 1
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: code.joined(separator: "\n")
                ))
                continue
            }

            // Blank lines separate blocks.
            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            // GFM pipe table: a cell row whose NEXT line is a delimiter
            // row (| --- | :---: |), then body rows while pipes continue.
            if trimmed.contains("|"),
               index + 1 < lines.count,
               isDelimiterRow(lines[index + 1]) {
                flushAll()
                let header = splitCells(trimmed)
                let aligns = splitCells(lines[index + 1]).map(columnAlign)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    if line.isEmpty || !line.contains("|") { break }
                    rows.append(splitCells(line))
                    index += 1
                }
                // Normalize to the header width — renderers build one
                // column per header cell.
                let width = header.count
                let normalized = rows.map { row -> [String] in
                    Array(row.prefix(width))
                        + Array(repeating: "", count: max(0, width - row.count))
                }
                blocks.append(.table(header: header, aligns: aligns, rows: normalized))
                continue
            }

            // ATX heading (# .. ###### followed by space).
            if let heading = headingLine(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Blockquote lines (lazy continuation included).
            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushLists()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                index += 1
                continue
            }
            if !quote.isEmpty {
                quote.append(trimmed)
                index += 1
                continue
            }

            // List items; a line right under a list item that isn't a new
            // marker continues that item (markdown lazy continuation).
            if let item = bulletItem(trimmed) {
                flushParagraph()
                if !ordered.isEmpty { blocks.append(.orderedList(ordered)); ordered = [] }
                bullets.append(item)
                index += 1
                continue
            }
            if let item = orderedItem(trimmed) {
                flushParagraph()
                if !bullets.isEmpty { blocks.append(.bulletList(bullets)); bullets = [] }
                ordered.append(item)
                index += 1
                continue
            }
            if !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + trimmed
                index += 1
                continue
            }
            if !ordered.isEmpty {
                ordered[ordered.count - 1] += " " + trimmed
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushAll()
        return blocks
    }

    /// Inline-styled text (bold, italic, code, links) — the intrinsic
    /// `AttributedString` markdown parsing restricted to inline syntax so
    /// block structure stays in `blocks(from:)`. Falls back to the plain
    /// string when parsing throws.
    public static func inlineAttributedString(_ raw: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let parsed = try? AttributedString(markdown: raw, options: options) {
            return parsed
        }
        return AttributedString(raw)
    }

    /// Splits a table row into cells at unescaped pipes; leading/trailing
    /// pipes are optional, cells are whitespace-trimmed, and `\|` renders
    /// as a literal pipe (the backslash is dropped).
    static func splitCells(_ line: String) -> [String] {
        var body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// A table delimiter row: every cell is dashes (spaces allowed) with
    /// optional leading/trailing colons for alignment.
    static func isDelimiterRow(_ line: String) -> Bool {
        let cells = splitCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            guard cell.contains("-") else { return false }
            return cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    static func columnAlign(_ delimiterCell: String) -> ColumnAlign {
        let compact = delimiterCell.filter { $0 != " " }
        let left = compact.first == ":"
        let right = compact.last == ":"
        if left && right { return .center }
        if right { return .trailing }
        return .leading
    }

    private static func headingLine(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix { $0 == "#" }.count
        guard level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func bulletItem(_ line: String) -> String? {
        guard let marker = line.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let item = rest.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return nil }
        return item
    }

    private static func orderedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.first == "." || rest.first == ")" else { return nil }
        let after = rest.dropFirst()
        guard after.first == " " || after.first == "\t" else { return nil }
        let item = after.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return nil }
        return item
    }
}
