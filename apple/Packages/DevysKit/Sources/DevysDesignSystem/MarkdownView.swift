public import SwiftUI

/// Renders Markdown as native text: headings, prose, lists, quotes, code and tables.
/// Links are sanitized by the parser and code stays inert.
public struct MarkdownView: View {
    private let blocks: [MarkdownBlock]

    public init(_ source: String) {
        blocks = MarkdownBlockParser.parse(source)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level, let text):
                    Text(text).font(level <= 1 ? DevysTypography.title : DevysTypography.heading).foregroundStyle(DevysColors.ink)
                case .prose(let text):
                    Text(text).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
                case .bullet(let text, let depth):
                    row("•", text, depth: depth)
                case .numbered(let marker, let text, let depth):
                    row(marker, text, depth: depth)
                case .blockquote(let text):
                    Text(text).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Capsule().fill(DevysColors.hairline).frame(width: 3) }
                case .code(let text, _):
                    Text(text).font(DevysTypography.data).foregroundStyle(DevysColors.ink)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .table(let headers, let rows):
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow { ForEach(headers.indices, id: \.self) { Text(headers[$0]).font(DevysTypography.label) } }
                        ForEach(rows.indices, id: \.self) { row in
                            GridRow { ForEach(rows[row].indices, id: \.self) { Text(rows[row][$0]).font(DevysTypography.body) } }
                        }
                    }
                    .foregroundStyle(DevysColors.ink)
                case .horizontalRule:
                    Rectangle().fill(DevysColors.hairline).frame(height: 1)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ marker: String, _ text: AttributedString, depth: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker).font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
            Text(text).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
        }
        .padding(.leading, CGFloat(depth) * 14)
    }
}
