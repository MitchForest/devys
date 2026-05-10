import Foundation

struct MarkdownBlock: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: Kind

    enum Kind: Equatable, Sendable {
        case heading(level: Int, attributed: AttributedString)
        case prose(AttributedString)
        case bullet(attributed: AttributedString, depth: Int)
        case numbered(marker: String, attributed: AttributedString, depth: Int)
        case blockquote(AttributedString)
        case code(String)
        case horizontalRule
    }
}

enum MarkdownDocumentParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var proseLines: [String] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var inFence = false

        func append(_ kind: MarkdownBlock.Kind) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind))
        }

        func flushProse() {
            guard !proseLines.isEmpty else { return }
            let joined = proseLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                append(.prose(inlineMarkdown(joined)))
            }
            proseLines.removeAll(keepingCapacity: true)
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            append(.blockquote(inlineMarkdown(quoteLines.joined(separator: "\n"))))
            quoteLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
        }

        for line in source.components(separatedBy: "\n") {
            let trimmedFront = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmedFront.hasPrefix("```") {
                if inFence {
                    flushCode()
                    inFence = false
                } else {
                    flushProse()
                    flushQuote()
                    inFence = true
                }
                continue
            }
            if inFence {
                codeLines.append(line)
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushProse()
                flushQuote()
                continue
            }

            if isHorizontalRule(line) {
                flushProse()
                flushQuote()
                append(.horizontalRule)
                continue
            }

            if let (level, body) = parseHeading(line) {
                flushProse()
                flushQuote()
                append(.heading(level: level, attributed: inlineMarkdown(body)))
                continue
            }

            if let quoteBody = parseBlockquote(line) {
                flushProse()
                quoteLines.append(quoteBody)
                continue
            } else if !quoteLines.isEmpty {
                flushQuote()
            }

            if let (depth, body) = parseBullet(line) {
                flushProse()
                flushQuote()
                append(.bullet(attributed: inlineMarkdown(body), depth: depth))
                continue
            }

            if let (depth, marker, body) = parseNumbered(line) {
                flushProse()
                flushQuote()
                append(.numbered(marker: marker, attributed: inlineMarkdown(body), depth: depth))
                continue
            }

            proseLines.append(line)
        }

        if inFence {
            flushCode()
        }
        flushProse()
        flushQuote()
        return blocks
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3,
              let first = trimmed.first,
              first == "-" || first == "*" || first == "_" else {
            return false
        }
        return trimmed.allSatisfy { $0 == first }
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
                if level > 6 { return nil }
            } else {
                break
            }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let afterHashes = line.dropFirst(level)
        guard afterHashes.first == " " else { return nil }
        let body = afterHashes.dropFirst()
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return (level, body)
    }

    private static func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.first == ">" else { return nil }
        var rest = trimmed.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    private static func parseBullet(_ line: String) -> (Int, String)? {
        var indentSpaces = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " { indentSpaces += 1 }
            else if character == "\t" { indentSpaces += 4 }
            else { break }
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }
        let marker = line[index]
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let after = line.index(after: index)
        guard after < line.endIndex, line[after] == " " else { return nil }
        let bodyStart = line.index(after: after)
        return (indentSpaces / 2, String(line[bodyStart...]))
    }

    private static func parseNumbered(_ line: String) -> (Int, String, String)? {
        var indentSpaces = 0
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == " " { indentSpaces += 1 }
            else if character == "\t" { indentSpaces += 4 }
            else { break }
            index = line.index(after: index)
        }
        var digitsEnd = index
        while digitsEnd < line.endIndex, line[digitsEnd].isNumber {
            digitsEnd = line.index(after: digitsEnd)
        }
        guard digitsEnd > index,
              digitsEnd < line.endIndex,
              line[digitsEnd] == "." else {
            return nil
        }
        let afterDot = line.index(after: digitsEnd)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let bodyStart = line.index(after: afterDot)
        let digits = String(line[index..<digitsEnd])
        return (indentSpaces / 2, "\(digits).", String(line[bodyStart...]))
    }

    private static func inlineMarkdown(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = true
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return attributed
        }
        return AttributedString(source)
    }
}
