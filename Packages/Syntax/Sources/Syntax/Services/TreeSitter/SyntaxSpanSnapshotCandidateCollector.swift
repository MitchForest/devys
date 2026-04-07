import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Text

struct SyntaxSpanSnapshotLineLayout {
    let snapshot: DocumentSnapshot
    let lineStartOffsets: [Int]
    let lineLengths: [Int]

    init(snapshot: DocumentSnapshot) {
        self.snapshot = snapshot
        self.lineStartOffsets = (0..<snapshot.lineCount).map { lineIndex in
            snapshot.offset(
                of: TextPoint(line: lineIndex, column: 0),
                encoding: .utf16
            )
        }
        self.lineLengths = (0..<snapshot.lineCount).map { lineIndex in
            snapshot.line(lineIndex).text.utf16.count
        }
    }

    func visibleUTF16Range(for lineRange: Range<Int>?) -> NSRange? {
        guard let lineRange else { return nil }

        let lowerBound = lineStartOffsets[lineRange.lowerBound]
        let upperBound: Int

        if lineRange.upperBound >= snapshot.lineCount {
            upperBound = snapshot.utf16Length
        } else {
            upperBound = lineStartOffsets[lineRange.upperBound]
        }

        return NSRange(lowerBound..<max(lowerBound, upperBound))
    }
}

enum SyntaxSpanSnapshotCandidateCollector {
    static func collect(
        from layerTreeSnapshot: LanguageLayerTreeSnapshot,
        layout: SyntaxSpanSnapshotLineLayout,
        theme: SyntaxTheme,
        normalizedLineRange: Range<Int>?
    ) -> [Int: [SyntaxHighlightCandidate]] {
        let queryRange = layout.visibleUTF16Range(for: normalizedLineRange)
            ?? NSRange(0..<layout.snapshot.utf16Length)
        let highlights = (try? layerTreeSnapshot.highlights(
            in: queryRange,
            provider: textProvider(for: layout.snapshot)
        )) ?? []

        var lineCandidates: [Int: [SyntaxHighlightCandidate]] = [:]

        for (highlightOrder, highlight) in highlights.enumerated() {
            guard let envelope = candidateEnvelope(
                from: highlight,
                snapshot: layout.snapshot,
                theme: theme,
                highlightOrder: highlightOrder
            ) else {
                continue
            }

            append(
                envelope,
                into: &lineCandidates,
                normalizedLineRange: normalizedLineRange,
                layout: layout
            )
        }

        return lineCandidates
    }

    static func normalize(
        _ candidates: [SyntaxHighlightCandidate]
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

            appendNormalizedSpan(
                SyntaxThemedSpan(
                    range: segment,
                    captureName: winner.captureName,
                    style: winner.style
                ),
                into: &normalized
            )
        }

        return normalized
    }

    private static func candidateEnvelope(
        from highlight: NamedRange,
        snapshot: DocumentSnapshot,
        theme: SyntaxTheme,
        highlightOrder: Int
    ) -> SyntaxHighlightCandidateEnvelope? {
        let globalLowerBound = highlight.range.location
        let globalUpperBound = NSMaxRange(highlight.range)
        guard globalLowerBound < globalUpperBound else { return nil }

        let startLine = snapshot.point(
            at: globalLowerBound,
            encoding: .utf16
        ).line
        let endLine = snapshot.point(
            at: max(globalLowerBound, globalUpperBound - 1),
            encoding: .utf16
        ).line
        guard startLine <= endLine else { return nil }

        let captureName = highlight.name
        return SyntaxHighlightCandidateEnvelope(
            lineRange: startLine...endLine,
            candidate: SyntaxHighlightCandidate(
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
        _ envelope: SyntaxHighlightCandidateEnvelope,
        into lineCandidates: inout [Int: [SyntaxHighlightCandidate]],
        normalizedLineRange: Range<Int>?,
        layout: SyntaxSpanSnapshotLineLayout
    ) {
        for lineIndex in envelope.lineRange {
            if let normalizedLineRange,
               !normalizedLineRange.contains(lineIndex) {
                continue
            }

            let lineStart = layout.lineStartOffsets[lineIndex]
            let lineEnd = lineStart + layout.lineLengths[lineIndex]
            let localLowerBound = max(envelope.candidate.range.lowerBound, lineStart) - lineStart
            let localUpperBound = min(envelope.candidate.range.upperBound, lineEnd) - lineStart
            guard localLowerBound < localUpperBound else { continue }

            lineCandidates[lineIndex, default: []].append(
                SyntaxHighlightCandidate(
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

    private static func appendNormalizedSpan(
        _ span: SyntaxThemedSpan,
        into normalized: inout [SyntaxThemedSpan]
    ) {
        if let last = normalized.last,
           last.captureName == span.captureName,
           last.style == span.style,
           last.range.upperBound == span.range.lowerBound {
            normalized[normalized.count - 1] = SyntaxThemedSpan(
                range: last.range.lowerBound..<span.range.upperBound,
                captureName: span.captureName,
                style: span.style
            )
            return
        }

        normalized.append(span)
    }

    private static func hasLowerPrecedence(
        _ lhs: SyntaxHighlightCandidate,
        _ rhs: SyntaxHighlightCandidate
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
}

struct SyntaxHighlightCandidate: Sendable {
    let range: Range<Int>
    let captureName: String
    let style: SyntaxThemeResolvedStyle
    let specificity: Int
    let globalLength: Int
    let order: Int
}

struct SyntaxHighlightCandidateEnvelope: Sendable {
    let lineRange: ClosedRange<Int>
    let candidate: SyntaxHighlightCandidate
}
