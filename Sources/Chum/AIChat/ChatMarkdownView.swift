import SwiftUI
import ChumCore

/// One parsed markdown block in an assistant chat bubble. Headings, lists,
/// quotes, and code fences get their own layout; inline styling (bold,
/// italic, code, links) renders through `ChatMarkdown.inlineAttributedString`.
struct ChatMarkdownBlock: View {
    let block: ChatMarkdown.Block

    var body: some View {
        switch block {
        case .paragraph(let text):
            MarkdownText(text)

        case .heading(let level, let text):
            MarkdownText(text)
                .font(.system(size: level <= 2 ? 14 : 13, weight: .semibold))

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        MarkdownText(items[index])
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                        MarkdownText(items[index])
                    }
                }
            }

        case .codeBlock(_, let code):
            // Code scrolls horizontally instead of wrapping — line breaks
            // the model produced stay meaningful.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.10)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )

        case .blockQuote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 2)
                MarkdownText(text)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)

        case .table(let header, let aligns, let rows):
            // Grid keeps columns aligned across rows; wide tables scroll
            // horizontally instead of crushing the cells.
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            MarkdownText(header[column])
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: cellAlignment(aligns, column))
                        }
                    }
                    GridRow {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row].indices, id: \.self) { column in
                                MarkdownText(rows[row][column])
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: cellAlignment(aligns, column))
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Column alignment from the delimiter row; missing entries lead.
    private func cellAlignment(_ aligns: [ChatMarkdown.ColumnAlign], _ column: Int) -> Alignment {
        guard column < aligns.count else { return .leading }
        switch aligns[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Inline-styled text with the bubble's default font and selectable copy.
private struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(ChatMarkdown.inlineAttributedString(text))
    }
}
