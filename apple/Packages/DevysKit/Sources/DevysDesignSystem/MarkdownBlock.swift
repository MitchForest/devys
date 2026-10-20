package import Foundation

/// Bounded Markdown blocks shared by Files and Bot replies. The model is
/// presentation-only: links are sanitized during parsing and code is inert.
package struct MarkdownBlock: Identifiable, Equatable {
    package let id: Int
    package let kind: Kind

    package enum Kind: Equatable {
        case heading(level: Int, text: AttributedString)
        case prose(AttributedString)
        case bullet(text: AttributedString, depth: Int)
        case numbered(marker: String, text: AttributedString, depth: Int)
        case blockquote(AttributedString)
        case code(text: String, language: String?)
        case table(headers: [AttributedString], rows: [[AttributedString]])
        case horizontalRule
    }
}

package enum MarkdownBlockParser {
    package static func parse(_ source: String) -> [MarkdownBlock] {
        parse(source.components(separatedBy: .newlines))
    }

    package static func parse(_ lines: [String]) -> [MarkdownBlock] {
        var state = MarkdownParseState()
        var index = 0
        while index < lines.count {
            if index + 1 < lines.count,
               let headers = tableCells(lines[index]),
               isTableDivider(lines[index + 1], columnCount: headers.count) {
                var rows: [[String]] = []
                index += 2
                while index < lines.count,
                      let cells = tableCells(lines[index]),
                      cells.count == headers.count {
                    rows.append(cells)
                    index += 1
                }
                state.consumeTable(headers: headers, rows: rows)
                continue
            }
            state.consume(lines[index])
            index += 1
        }
        return state.finish()
    }

    package static func inlineMarkdown(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = true
        let parsed = (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
        return removingUnsafeLinks(from: parsed)
    }

    package static func isSafeLink(_ url: URL) -> Bool {
        if url.absoluteString.hasPrefix("#") { return true }
        return url.scheme == "https" || url.scheme == "mailto"
    }

    fileprivate static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3,
              let first = trimmed.first,
              first == "-" || first == "*" || first == "_"
        else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    fileprivate static func parseHeading(_ line: String) -> (level: Int, body: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let afterHashes = line.dropFirst(level)
        guard afterHashes.first == " " else { return nil }
        let body = afterHashes.dropFirst()
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return (level, body)
    }

    fileprivate static func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.first == ">" else { return nil }
        return String(trimmed.dropFirst().drop(while: { $0 == " " }))
    }

    fileprivate static func parseBullet(_ line: String) -> (depth: Int, body: String)? {
        let item = indentedContent(line)
        guard let marker = item.content.first,
              marker == "-" || marker == "*" || marker == "+",
              item.content.dropFirst().first == " "
        else { return nil }
        return (item.depth, String(item.content.dropFirst(2)))
    }

    fileprivate static func parseNumbered(_ line: String) -> NumberedItem? {
        let item = indentedContent(line)
        let digits = item.content.prefix(while: \.isNumber)
        let suffix = item.content.dropFirst(digits.count)
        guard !digits.isEmpty, suffix.hasPrefix(". ") else { return nil }
        return NumberedItem(
            depth: item.depth,
            marker: "\(digits).",
            body: String(suffix.dropFirst(2))
        )
    }

    fileprivate struct NumberedItem {
        let depth: Int
        let marker: String
        let body: String
    }

    private static func indentedContent(_ line: String) -> (depth: Int, content: Substring) {
        var spaces = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == " " { spaces += 1 } else if line[index] == "\t" { spaces += 4 } else {
                break
            }
            index = line.index(after: index)
        }
        return (spaces / 2, line[index...])
    }

    private static func tableCells(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isTableDivider(_ line: String, columnCount: Int) -> Bool {
        guard let cells = tableCells(line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            let rule = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return rule.count >= 3 && rule.allSatisfy { $0 == "-" }
        }
    }

    private static func removingUnsafeLinks(from source: AttributedString) -> AttributedString {
        var result = source
        var unsafeRanges: [Range<AttributedString.Index>] = []
        for run in source.runs {
            if let link = run.link, !isSafeLink(link) {
                unsafeRanges.append(run.range)
            }
        }
        for range in unsafeRanges {
            result[range].link = nil
        }
        return result
    }
}

private struct MarkdownParseState {
    private var blocks: [MarkdownBlock] = []
    private var proseLines: [String] = []
    private var quoteLines: [String] = []
    private var codeLines: [String] = []
    private var fenceLanguage: String?
    private var inFence = false

    mutating func consume(_ line: String) {
        if consumeFence(line) { return }
        if inFence {
            codeLines.append(line)
            return
        }
        if consumeBlankOrHorizontalRule(line) { return }
        if consumeHeading(line) { return }
        if consumeBlockquote(line) { return }
        if consumeListItem(line) { return }
        proseLines.append(line)
    }

    mutating func consumeTable(headers: [String], rows: [[String]]) {
        flushProse()
        flushQuote()
        append(
            .table(
                headers: headers.map(MarkdownBlockParser.inlineMarkdown),
                rows: rows.map { $0.map(MarkdownBlockParser.inlineMarkdown) }
            ))
    }

    mutating func finish() -> [MarkdownBlock] {
        if inFence { flushCode() }
        flushProse()
        flushQuote()
        return blocks
    }

    private mutating func consumeFence(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("```") else { return false }
        if inFence {
            flushCode()
            inFence = false
        } else {
            flushProse()
            flushQuote()
            let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            fenceLanguage = language.isEmpty ? nil : language.lowercased()
            inFence = true
        }
        return true
    }

    private mutating func consumeBlankOrHorizontalRule(_ line: String) -> Bool {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            flushProse()
            flushQuote()
            return true
        }
        guard MarkdownBlockParser.isHorizontalRule(line) else { return false }
        flushProse()
        flushQuote()
        append(.horizontalRule)
        return true
    }

    private mutating func consumeHeading(_ line: String) -> Bool {
        guard let heading = MarkdownBlockParser.parseHeading(line) else { return false }
        flushProse()
        flushQuote()
        append(.heading(level: heading.level, text: MarkdownBlockParser.inlineMarkdown(heading.body)))
        return true
    }

    private mutating func consumeBlockquote(_ line: String) -> Bool {
        if let body = MarkdownBlockParser.parseBlockquote(line) {
            flushProse()
            quoteLines.append(body)
            return true
        }
        if !quoteLines.isEmpty { flushQuote() }
        return false
    }

    private mutating func consumeListItem(_ line: String) -> Bool {
        if let bullet = MarkdownBlockParser.parseBullet(line) {
            flushProse()
            flushQuote()
            append(.bullet(text: MarkdownBlockParser.inlineMarkdown(bullet.body), depth: bullet.depth))
            return true
        }
        if let numbered = MarkdownBlockParser.parseNumbered(line) {
            flushProse()
            flushQuote()
            append(
                .numbered(
                    marker: numbered.marker,
                    text: MarkdownBlockParser.inlineMarkdown(numbered.body),
                    depth: numbered.depth
                ))
            return true
        }
        return false
    }

    private mutating func append(_ kind: MarkdownBlock.Kind) {
        blocks.append(MarkdownBlock(id: blocks.count, kind: kind))
    }

    private mutating func flushProse() {
        guard !proseLines.isEmpty else { return }
        let joined = proseLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { append(.prose(MarkdownBlockParser.inlineMarkdown(joined))) }
        proseLines.removeAll(keepingCapacity: true)
    }

    private mutating func flushQuote() {
        guard !quoteLines.isEmpty else { return }
        append(.blockquote(MarkdownBlockParser.inlineMarkdown(quoteLines.joined(separator: "\n"))))
        quoteLines.removeAll(keepingCapacity: true)
    }

    private mutating func flushCode() {
        append(.code(text: codeLines.joined(separator: "\n"), language: fenceLanguage))
        codeLines.removeAll(keepingCapacity: true)
        fenceLanguage = nil
    }
}
