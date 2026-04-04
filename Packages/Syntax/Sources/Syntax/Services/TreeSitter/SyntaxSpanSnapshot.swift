import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Text

public struct SyntaxThemedSpan: Sendable, Equatable {
    public let range: Range<Int>
    public let captureName: String
    public let style: SyntaxThemeResolvedStyle

    public init(
        range: Range<Int>,
        captureName: String,
        style: SyntaxThemeResolvedStyle
    ) {
        self.range = range
        self.captureName = captureName
        self.style = style
    }
}

public struct SyntaxLineSpanSnapshot: Sendable, Equatable {
    public let lineIndex: Int
    public let spans: [SyntaxThemedSpan]

    public init(
        lineIndex: Int,
        spans: [SyntaxThemedSpan]
    ) {
        self.lineIndex = lineIndex
        self.spans = spans
    }
}

public struct SyntaxSpanSnapshot: Sendable, Equatable {
    public let revision: UInt64
    public let documentVersion: DocumentVersion
    public let themeName: String
    public let lineCount: Int

    private let linesByIndex: [Int: SyntaxLineSpanSnapshot]

    public init(
        revision: UInt64,
        documentVersion: DocumentVersion,
        themeName: String,
        lineCount: Int,
        linesByIndex: [Int: SyntaxLineSpanSnapshot]
    ) {
        self.revision = revision
        self.documentVersion = documentVersion
        self.themeName = themeName
        self.lineCount = lineCount
        self.linesByIndex = linesByIndex
    }

    public func line(_ index: Int) -> SyntaxLineSpanSnapshot {
        linesByIndex[index] ?? SyntaxLineSpanSnapshot(lineIndex: index, spans: [])
    }

    public func lines(in range: Range<Int>) -> [SyntaxLineSpanSnapshot] {
        let lowerBound = max(0, min(range.lowerBound, lineCount))
        let upperBound = max(lowerBound, min(range.upperBound, lineCount))
        return (lowerBound..<upperBound).map(line)
    }

    public func merging(
        revision: UInt64,
        documentVersion: DocumentVersion,
        themeName: String,
        lineCount: Int,
        lines: [SyntaxLineSpanSnapshot]
    ) -> SyntaxSpanSnapshot {
        var merged = linesByIndex
        for line in lines {
            merged[line.lineIndex] = line
        }

        return SyntaxSpanSnapshot(
            revision: revision,
            documentVersion: documentVersion,
            themeName: themeName,
            lineCount: lineCount,
            linesByIndex: merged
        )
    }

    public func removing(lineRanges: [SourceLineRange]) -> SyntaxSpanSnapshot {
        guard !lineRanges.isEmpty else { return self }

        var remaining = linesByIndex
        for range in lineRanges {
            for lineIndex in range.lowerBound..<range.upperBound {
                remaining.removeValue(forKey: lineIndex)
            }
        }

        return SyntaxSpanSnapshot(
            revision: revision,
            documentVersion: documentVersion,
            themeName: themeName,
            lineCount: lineCount,
            linesByIndex: remaining
        )
    }
}

public enum SyntaxSpanSnapshotBuilder {
    public static func build(
        documentSnapshot: DocumentSnapshot,
        documentState: SyntaxDocumentState,
        languageConfiguration: LanguageConfiguration,
        theme: SyntaxTheme,
        lineRange: Range<Int>? = nil
    ) -> SyntaxSpanSnapshot {
        let normalizedLineRange = normalizedRange(lineRange, lineCount: documentSnapshot.lineCount)

        guard documentSnapshot.lineCount > 0 else {
            return emptySnapshot(
                documentSnapshot: documentSnapshot,
                documentState: documentState,
                theme: theme
            )
        }

        guard documentState.tree.rootNode != nil else {
            return emptySnapshot(
                documentSnapshot: documentSnapshot,
                documentState: documentState,
                theme: theme
            )
        }

        let lineStartOffsets = lineStartOffsets(in: documentSnapshot)
        let lineLengths = lineLengths(in: documentSnapshot)
        let visibleUTF16Range: NSRange? = if let normalizedLineRange {
            utf16Range(
                for: normalizedLineRange,
                lineStartOffsets: lineStartOffsets,
                lineLengths: lineLengths,
                snapshot: documentSnapshot
            )
        } else {
            nil
        }
        var lineCandidates = lineCandidates(
            from: documentState.layerTreeSnapshot,
            documentSnapshot: documentSnapshot,
            theme: theme,
            normalizedLineRange: normalizedLineRange,
            utf16Range: visibleUTF16Range,
            lineStartOffsets: lineStartOffsets,
            lineLengths: lineLengths
        )

        if languageConfiguration.name == "Markdown" {
            applyMarkdownPresentationOverlays(
                into: &lineCandidates,
                documentSnapshot: documentSnapshot,
                theme: theme,
                normalizedLineRange: normalizedLineRange
            )
        }

        let linesByIndex = lineCandidates.reduce(into: [Int: SyntaxLineSpanSnapshot]()) { partialResult, entry in
            partialResult[entry.key] = SyntaxLineSpanSnapshot(
                lineIndex: entry.key,
                spans: normalize(entry.value)
            )
        }

        return SyntaxSpanSnapshot(
            revision: documentState.syntaxRevision,
            documentVersion: documentState.documentVersion,
            themeName: theme.name,
            lineCount: documentSnapshot.lineCount,
            linesByIndex: linesByIndex
        )
    }

    private static func emptySnapshot(
        documentSnapshot: DocumentSnapshot,
        documentState: SyntaxDocumentState,
        theme: SyntaxTheme
    ) -> SyntaxSpanSnapshot {
        SyntaxSpanSnapshot(
            revision: documentState.syntaxRevision,
            documentVersion: documentState.documentVersion,
            themeName: theme.name,
            lineCount: documentSnapshot.lineCount,
            linesByIndex: [:]
        )
    }

    private static func lineCandidates(
        from layerTreeSnapshot: LanguageLayerTreeSnapshot,
        documentSnapshot: DocumentSnapshot,
        theme: SyntaxTheme,
        normalizedLineRange: Range<Int>?,
        utf16Range: NSRange?,
        lineStartOffsets: [Int],
        lineLengths: [Int]
    ) -> [Int: [HighlightCandidate]] {
        var lineCandidates: [Int: [HighlightCandidate]] = [:]
        var highlightOrder = 0
        let highlights: [NamedRange]

        do {
            let queryRange = utf16Range ?? NSRange(0..<documentSnapshot.utf16Length)
            highlights = try layerTreeSnapshot.highlights(
                in: queryRange,
                provider: textProvider(for: documentSnapshot)
            )
        } catch {
            return [:]
        }

        for highlight in highlights {
            defer { highlightOrder += 1 }

            guard let envelope = candidateEnvelope(
                from: highlight,
                documentSnapshot: documentSnapshot,
                theme: theme,
                highlightOrder: highlightOrder
            ) else {
                continue
            }

            append(
                envelope,
                into: &lineCandidates,
                normalizedLineRange: normalizedLineRange,
                lineStartOffsets: lineStartOffsets,
                lineLengths: lineLengths
            )
        }

        return lineCandidates
    }

    private static func candidateEnvelope(
        from highlight: NamedRange,
        documentSnapshot: DocumentSnapshot,
        theme: SyntaxTheme,
        highlightOrder: Int
    ) -> HighlightCandidateEnvelope? {
        let captureName = highlight.name

        let globalLowerBound = highlight.range.location
        let globalUpperBound = NSMaxRange(highlight.range)
        guard globalLowerBound < globalUpperBound else { return nil }

        let startLine = documentSnapshot.point(
            at: globalLowerBound,
            encoding: .utf16
        ).line
        let endLine = documentSnapshot.point(
            at: max(globalLowerBound, globalUpperBound - 1),
            encoding: .utf16
        ).line
        guard startLine <= endLine else { return nil }

        return HighlightCandidateEnvelope(
            lineRange: startLine...endLine,
            candidate: HighlightCandidate(
                range: globalLowerBound..<globalUpperBound,
                captureName: captureName,
                style: theme.resolve(captureNames: [captureName]),
                specificity: highlight.nameComponents.count,
                globalLength: globalUpperBound - globalLowerBound,
                order: highlightOrder
            )
        )
    }

    private static func append(
        _ envelope: HighlightCandidateEnvelope,
        into lineCandidates: inout [Int: [HighlightCandidate]],
        normalizedLineRange: Range<Int>?,
        lineStartOffsets: [Int],
        lineLengths: [Int]
    ) {
        for lineIndex in envelope.lineRange {
            if let normalizedLineRange,
               normalizedLineRange.contains(lineIndex) == false {
                continue
            }

            let lineStart = lineStartOffsets[lineIndex]
            let lineEnd = lineStart + lineLengths[lineIndex]
            let localLowerBound = max(envelope.candidate.range.lowerBound, lineStart) - lineStart
            let localUpperBound = min(envelope.candidate.range.upperBound, lineEnd) - lineStart
            guard localLowerBound < localUpperBound else { continue }

            lineCandidates[lineIndex, default: []].append(
                HighlightCandidate(
                    range: localLowerBound..<localUpperBound,
                    captureName: envelope.candidate.captureName,
                    style: envelope.candidate.style,
                    specificity: envelope.candidate.specificity,
                    globalLength: envelope.candidate.globalLength,
                    order: envelope.candidate.order
                )
            )
        }
    }

    private static func normalizedRange(
        _ range: Range<Int>?,
        lineCount: Int
    ) -> Range<Int>? {
        guard let range else { return nil }
        let lowerBound = max(0, min(range.lowerBound, lineCount))
        let upperBound = max(lowerBound, min(range.upperBound, lineCount))
        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }

    private static func utf16Range(
        for lineRange: Range<Int>,
        lineStartOffsets: [Int],
        lineLengths: [Int],
        snapshot: DocumentSnapshot
    ) -> NSRange {
        let lowerBound = lineStartOffsets[lineRange.lowerBound]
        let upperBound: Int = if lineRange.upperBound >= snapshot.lineCount {
            snapshot.utf16Length
        } else {
            lineStartOffsets[lineRange.upperBound]
        }
        return NSRange(lowerBound..<max(lowerBound, upperBound))
    }

    private static func lineStartOffsets(
        in snapshot: DocumentSnapshot
    ) -> [Int] {
        (0..<snapshot.lineCount).map { lineIndex in
            snapshot.offset(
                of: TextPoint(line: lineIndex, column: 0),
                encoding: .utf16
            )
        }
    }

    private static func lineLengths(
        in snapshot: DocumentSnapshot
    ) -> [Int] {
        (0..<snapshot.lineCount).map { lineIndex in
            snapshot.line(lineIndex).text.utf16.count
        }
    }

    private static func normalize(
        _ candidates: [HighlightCandidate]
    ) -> [SyntaxThemedSpan] {
        guard !candidates.isEmpty else { return [] }

        let boundaries = Set(
            candidates.flatMap { candidate in
                [
                    candidate.range.lowerBound,
                    candidate.range.upperBound
                ]
            }
        ).sorted()

        guard boundaries.count >= 2 else { return [] }

        var normalized: [SyntaxThemedSpan] = []

        for index in 0..<(boundaries.count - 1) {
            let segment = boundaries[index]..<boundaries[index + 1]
            guard segment.lowerBound < segment.upperBound else { continue }

            let coveringCandidates = candidates.filter { candidate in
                candidate.range.lowerBound <= segment.lowerBound &&
                segment.upperBound <= candidate.range.upperBound
            }
            guard let winner = coveringCandidates.max(by: hasLowerPrecedence) else {
                continue
            }

            let span = SyntaxThemedSpan(
                range: segment,
                captureName: winner.captureName,
                style: winner.style
            )

            if let last = normalized.last,
               last.captureName == span.captureName,
               last.style == span.style,
               last.range.upperBound == span.range.lowerBound {
                normalized[normalized.count - 1] = SyntaxThemedSpan(
                    range: last.range.lowerBound..<span.range.upperBound,
                    captureName: span.captureName,
                    style: span.style
                )
            } else {
                normalized.append(span)
            }
        }

        return normalized
    }

    private static func hasLowerPrecedence(
        _ lhs: HighlightCandidate,
        _ rhs: HighlightCandidate
    ) -> Bool {
        if lhs.globalLength != rhs.globalLength {
            return lhs.globalLength > rhs.globalLength
        }

        if lhs.specificity != rhs.specificity {
            return lhs.specificity < rhs.specificity
        }

        return lhs.order < rhs.order
    }

    private static func textProvider(
        for snapshot: DocumentSnapshot
    ) -> SwiftTreeSitter.Predicate.TextProvider {
        { range, _ in
            let lowerBound = max(0, min(range.location, snapshot.utf16Length))
            let upperBound = max(
                lowerBound,
                min(range.location + range.length, snapshot.utf16Length)
            )
            guard upperBound > lowerBound else { return "" }

            let startPoint = snapshot.point(at: lowerBound, encoding: .utf16)
            let endPoint = snapshot.point(at: upperBound, encoding: .utf16)
            let startUTF8 = snapshot.offset(of: startPoint, encoding: .utf8)
            let endUTF8 = snapshot.offset(of: endPoint, encoding: .utf8)
            return snapshot.slice(TextByteRange(startUTF8, endUTF8)).text
        }
    }

    private static func applyMarkdownPresentationOverlays(
        into lineCandidates: inout [Int: [HighlightCandidate]],
        documentSnapshot: DocumentSnapshot,
        theme: SyntaxTheme,
        normalizedLineRange: Range<Int>?
    ) {
        var nextOrder = (lineCandidates.values.flatMap { $0 }.map(\.order).max() ?? -1) + 1

        for lineIndex in 0..<documentSnapshot.lineCount {
            if let normalizedLineRange,
               normalizedLineRange.contains(lineIndex) == false {
                continue
            }

            let overlays = markdownOverlayCandidates(
                for: documentSnapshot.line(lineIndex).text,
                theme: theme,
                startingOrder: nextOrder
            )
            nextOrder += overlays.count

            guard overlays.isEmpty == false else { continue }
            lineCandidates[lineIndex, default: []].append(contentsOf: overlays)
        }
    }

    private static func markdownOverlayCandidates(
        for lineText: String,
        theme: SyntaxTheme,
        startingOrder: Int
    ) -> [HighlightCandidate] {
        let nsLine = lineText as NSString
        let lineLength = nsLine.length
        var overlays: [HighlightCandidate] = []
        var nextOrder = startingOrder

        func append(range: Range<Int>, captureName: String) {
            guard range.lowerBound < range.upperBound else { return }

            overlays.append(
                HighlightCandidate(
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

        var prefixIndex = 0
        while prefixIndex < lineLength,
              prefixIndex < 3,
              nsLine.character(at: prefixIndex) == 0x20 {
            prefixIndex += 1
        }

        if prefixIndex < lineLength {
            let character = nsLine.character(at: prefixIndex)

            if character == 0x23 {
                var markerEnd = prefixIndex
                while markerEnd < lineLength,
                      nsLine.character(at: markerEnd) == 0x23,
                      markerEnd - prefixIndex < 6 {
                    markerEnd += 1
                }

                if markerEnd < lineLength, nsLine.character(at: markerEnd) == 0x20 {
                    append(range: prefixIndex..<(markerEnd + 1), captureName: "punctuation.special")
                    if markerEnd + 1 < lineLength {
                        append(range: (markerEnd + 1)..<lineLength, captureName: "text.title")
                    }
                }
            } else if character == 0x2D || character == 0x2B || character == 0x2A {
                if prefixIndex + 1 < lineLength, nsLine.character(at: prefixIndex + 1) == 0x20 {
                    append(range: prefixIndex..<(prefixIndex + 2), captureName: "punctuation.special")
                }
            } else if character >= 0x30, character <= 0x39 {
                var numberEnd = prefixIndex
                while numberEnd < lineLength {
                    let digit = nsLine.character(at: numberEnd)
                    guard digit >= 0x30, digit <= 0x39 else { break }
                    numberEnd += 1
                }

                if numberEnd < lineLength,
                   (nsLine.character(at: numberEnd) == 0x2E || nsLine.character(at: numberEnd) == 0x29),
                   numberEnd + 1 < lineLength,
                   nsLine.character(at: numberEnd + 1) == 0x20 {
                    append(range: prefixIndex..<(numberEnd + 2), captureName: "punctuation.special")
                }
            }
        }

        var index = 0
        while index < lineLength {
            guard nsLine.character(at: index) == 0x60 else {
                index += 1
                continue
            }

            let openingStart = index
            var delimiterLength = 0
            while index < lineLength, nsLine.character(at: index) == 0x60 {
                delimiterLength += 1
                index += 1
            }

            var searchIndex = index
            var closingStart: Int?

            while searchIndex < lineLength {
                guard nsLine.character(at: searchIndex) == 0x60 else {
                    searchIndex += 1
                    continue
                }

                var candidateLength = 0
                while searchIndex + candidateLength < lineLength,
                      nsLine.character(at: searchIndex + candidateLength) == 0x60 {
                    candidateLength += 1
                }

                if candidateLength == delimiterLength {
                    closingStart = searchIndex
                    break
                }

                searchIndex += max(candidateLength, 1)
            }

            guard let closingStart else {
                continue
            }

            append(
                range: openingStart..<(openingStart + delimiterLength),
                captureName: "punctuation.delimiter"
            )
            append(
                range: closingStart..<(closingStart + delimiterLength),
                captureName: "punctuation.delimiter"
            )

            if openingStart + delimiterLength < closingStart {
                append(
                    range: (openingStart + delimiterLength)..<closingStart,
                    captureName: "text.literal"
                )
            }

            index = closingStart + delimiterLength
        }

        return overlays
    }
}

private struct HighlightCandidate: Sendable {
    let range: Range<Int>
    let captureName: String
    let style: SyntaxThemeResolvedStyle
    let specificity: Int
    let globalLength: Int
    let order: Int
}

private struct HighlightCandidateEnvelope: Sendable {
    let lineRange: ClosedRange<Int>
    let candidate: HighlightCandidate
}
