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

        guard documentSnapshot.lineCount > 0,
              documentState.tree.rootNode != nil else {
            return emptySnapshot(
                documentSnapshot: documentSnapshot,
                documentState: documentState,
                theme: theme
            )
        }

        let lineLayout = SyntaxSpanSnapshotLineLayout(snapshot: documentSnapshot)
        var lineCandidates = SyntaxSpanSnapshotCandidateCollector.collect(
            from: documentState.layerTreeSnapshot,
            layout: lineLayout,
            theme: theme,
            normalizedLineRange: normalizedLineRange
        )

        if languageConfiguration.name == "Markdown" {
            SyntaxSpanSnapshotMarkdownOverlayBuilder.apply(
                into: &lineCandidates,
                documentSnapshot: documentSnapshot,
                theme: theme,
                normalizedLineRange: normalizedLineRange
            )
        }

        return makeSnapshot(
            documentSnapshot: documentSnapshot,
            documentState: documentState,
            theme: theme,
            lineCandidates: lineCandidates
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

    private static func normalizedRange(
        _ range: Range<Int>?,
        lineCount: Int
    ) -> Range<Int>? {
        guard let range else { return nil }
        let lowerBound = max(0, min(range.lowerBound, lineCount))
        let upperBound = max(lowerBound, min(range.upperBound, lineCount))
        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }
    private static func makeSnapshot(
        documentSnapshot: DocumentSnapshot,
        documentState: SyntaxDocumentState,
        theme: SyntaxTheme,
        lineCandidates: [Int: [SyntaxHighlightCandidate]]
    ) -> SyntaxSpanSnapshot {
        let linesByIndex = lineCandidates.reduce(into: [Int: SyntaxLineSpanSnapshot]()) { partialResult, entry in
            partialResult[entry.key] = SyntaxLineSpanSnapshot(
                lineIndex: entry.key,
                spans: SyntaxSpanSnapshotCandidateCollector.normalize(entry.value)
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
}
