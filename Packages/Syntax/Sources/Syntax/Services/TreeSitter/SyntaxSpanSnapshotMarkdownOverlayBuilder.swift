import Foundation
import Text

enum SyntaxSpanSnapshotMarkdownOverlayBuilder {
    static func apply(
        into lineCandidates: inout [Int: [SyntaxHighlightCandidate]],
        documentSnapshot: DocumentSnapshot,
        theme: SyntaxTheme,
        normalizedLineRange: Range<Int>?
    ) {
        var nextOrder = (lineCandidates.values.flatMap { $0 }.map(\.order).max() ?? -1) + 1

        for lineIndex in 0..<documentSnapshot.lineCount {
            if let normalizedLineRange,
               !normalizedLineRange.contains(lineIndex) {
                continue
            }

            let overlays = overlays(
                for: documentSnapshot.line(lineIndex).text,
                theme: theme,
                startingOrder: nextOrder
            )
            nextOrder += overlays.count

            guard !overlays.isEmpty else { continue }
            lineCandidates[lineIndex, default: []].append(contentsOf: overlays)
        }
    }

    private static func overlays(
        for lineText: String,
        theme: SyntaxTheme,
        startingOrder: Int
    ) -> [SyntaxHighlightCandidate] {
        var lineScanner = MarkdownLineScanner(
            lineText: lineText,
            theme: theme,
            startingOrder: startingOrder
        )
        return lineScanner.makeOverlays()
    }
}

private struct MarkdownLineScanner {
    private let nsLine: NSString
    private let lineLength: Int
    private let theme: SyntaxTheme
    private var overlays: [SyntaxHighlightCandidate] = []
    private var nextOrder: Int

    init(lineText: String, theme: SyntaxTheme, startingOrder: Int) {
        self.nsLine = lineText as NSString
        self.lineLength = nsLine.length
        self.theme = theme
        self.nextOrder = startingOrder
    }

    mutating func makeOverlays() -> [SyntaxHighlightCandidate] {
        appendPrefixOverlays()
        appendInlineCodeOverlays()
        return overlays
    }

    private mutating func appendPrefixOverlays() {
        let prefixIndex = indentationPrefixLength()
        guard prefixIndex < lineLength else { return }

        let character = nsLine.character(at: prefixIndex)

        if appendHeadingOverlay(at: prefixIndex, character: character) {
            return
        }

        if appendUnorderedListOverlay(at: prefixIndex, character: character) {
            return
        }

        appendOrderedListOverlay(at: prefixIndex, character: character)
    }

    private func indentationPrefixLength() -> Int {
        var prefixIndex = 0

        while prefixIndex < lineLength,
              prefixIndex < 3,
              nsLine.character(at: prefixIndex) == 0x20 {
            prefixIndex += 1
        }

        return prefixIndex
    }

    private mutating func appendInlineCodeOverlays() {
        var index = 0

        while index < lineLength {
            guard nsLine.character(at: index) == 0x60 else {
                index += 1
                continue
            }

            let openingStart = index
            let delimiterLength = consumeDelimiterLength(at: &index)

            guard let closingStart = matchingDelimiterStart(
                delimiterLength: delimiterLength,
                searchIndex: index
            ) else {
                continue
            }

            append(range: openingStart..<(openingStart + delimiterLength), captureName: "punctuation.delimiter")
            append(range: closingStart..<(closingStart + delimiterLength), captureName: "punctuation.delimiter")

            if openingStart + delimiterLength < closingStart {
                append(
                    range: (openingStart + delimiterLength)..<closingStart,
                    captureName: "text.literal"
                )
            }

            index = closingStart + delimiterLength
        }
    }

    private mutating func append(range: Range<Int>, captureName: String) {
        guard range.lowerBound < range.upperBound else { return }

        overlays.append(
            SyntaxHighlightCandidate(
                range: range,
                captureName: captureName,
                style: theme.resolve(captureNames: [captureName]),
                specificity: 100 + captureName.split(separator: ".").count,
                globalLength: range.count,
                order: nextOrder
            )
        )
        nextOrder += 1
    }

    private mutating func appendHeadingOverlay(at prefixIndex: Int, character: unichar) -> Bool {
        guard character == 0x23 else { return false }

        var markerEnd = prefixIndex
        while markerEnd < lineLength,
              nsLine.character(at: markerEnd) == 0x23,
              markerEnd - prefixIndex < 6 {
            markerEnd += 1
        }

        guard markerEnd < lineLength, nsLine.character(at: markerEnd) == 0x20 else {
            return false
        }

        append(range: prefixIndex..<(markerEnd + 1), captureName: "punctuation.special")

        if markerEnd + 1 < lineLength {
            append(range: (markerEnd + 1)..<lineLength, captureName: "text.title")
        }

        return true
    }

    private mutating func appendUnorderedListOverlay(at prefixIndex: Int, character: unichar) -> Bool {
        guard character == 0x2D || character == 0x2B || character == 0x2A else {
            return false
        }

        guard prefixIndex + 1 < lineLength, nsLine.character(at: prefixIndex + 1) == 0x20 else {
            return false
        }

        append(range: prefixIndex..<(prefixIndex + 2), captureName: "punctuation.special")
        return true
    }

    private mutating func appendOrderedListOverlay(at prefixIndex: Int, character: unichar) {
        guard character >= 0x30, character <= 0x39 else { return }

        var numberEnd = prefixIndex
        while numberEnd < lineLength {
            let digit = nsLine.character(at: numberEnd)
            guard digit >= 0x30, digit <= 0x39 else { break }
            numberEnd += 1
        }

        guard numberEnd < lineLength else { return }

        let marker = nsLine.character(at: numberEnd)
        guard marker == 0x2E || marker == 0x29 else { return }
        guard numberEnd + 1 < lineLength, nsLine.character(at: numberEnd + 1) == 0x20 else { return }

        append(range: prefixIndex..<(numberEnd + 2), captureName: "punctuation.special")
    }

    private mutating func consumeDelimiterLength(at index: inout Int) -> Int {
        let openingStart = index
        while index < lineLength, nsLine.character(at: index) == 0x60 {
            index += 1
        }
        return index - openingStart
    }

    private func matchingDelimiterStart(
        delimiterLength: Int,
        searchIndex startIndex: Int
    ) -> Int? {
        var searchIndex = startIndex

        while searchIndex < lineLength {
            guard nsLine.character(at: searchIndex) == 0x60 else {
                searchIndex += 1
                continue
            }

            let candidateLength = repeatedBacktickCount(startingAt: searchIndex)
            if candidateLength == delimiterLength {
                return searchIndex
            }

            searchIndex += max(candidateLength, 1)
        }

        return nil
    }

    private func repeatedBacktickCount(startingAt index: Int) -> Int {
        var count = 0

        while index + count < lineLength,
              nsLine.character(at: index + count) == 0x60 {
            count += 1
        }

        return count
    }
}
