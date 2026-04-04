// periphery:ignore:all - diff display snapshots are consumed by Metal rendering and tests
import Foundation
import Rendering
import Syntax

// swiftlint:disable file_length type_body_length
struct DiffDisplayText: Sendable, Equatable {
    let packet: TextRenderPacket
    let syntaxStatus: HighlightStatus?

    var countsAsActualHighlight: Bool {
        syntaxStatus?.countsAsActual == true
    }

    var isSyntaxTracked: Bool {
        syntaxStatus != nil
    }
}

struct VisibleUnifiedDiffDisplayRow: Identifiable, Sendable, Equatable {
    let rowIndex: Int
    let id: String
    let kind: UnifiedDiffRow.Kind
    let lineType: DiffLine.LineType
    let oldLineNumberPacket: TextRenderPacket?
    let newLineNumberPacket: TextRenderPacket?
    let prefixPacket: TextRenderPacket?
    let content: DiffDisplayText
}

struct SplitDiffDisplaySide: Sendable, Equatable {
    let lineType: DiffLine.LineType
    let lineNumberPacket: TextRenderPacket?
    let content: DiffDisplayText
}

struct VisibleSplitDiffDisplayRow: Identifiable, Sendable, Equatable {
    let rowIndex: Int
    let id: String
    let kind: SplitDiffRow.Kind
    let headerPacket: TextRenderPacket?
    let left: SplitDiffDisplaySide?
    let right: SplitDiffDisplaySide?
}

struct UnifiedDiffDisplaySnapshot: Sendable, Equatable {
    let visibleRowRange: ClosedRange<Int>
    let rows: [VisibleUnifiedDiffDisplayRow]
    let visibleSyntaxLineCount: Int
    let actualHighlightedLineCount: Int
    let staleHighlightedLineCount: Int

    var loadingLineCount: Int {
        max(0, visibleSyntaxLineCount - actualHighlightedLineCount - staleHighlightedLineCount)
    }

    var allVisibleSyntaxLinesActual: Bool {
        actualHighlightedLineCount == visibleSyntaxLineCount
    }
}

struct SplitDiffDisplaySnapshot: Sendable, Equatable {
    let visibleRowRange: ClosedRange<Int>
    let rows: [VisibleSplitDiffDisplayRow]
    let visibleSyntaxLineCount: Int
    let actualHighlightedLineCount: Int
    let staleHighlightedLineCount: Int

    var loadingLineCount: Int {
        max(0, visibleSyntaxLineCount - actualHighlightedLineCount - staleHighlightedLineCount)
    }

    var allVisibleSyntaxLinesActual: Bool {
        actualHighlightedLineCount == visibleSyntaxLineCount
    }
}

enum DiffDisplaySnapshot: Sendable, Equatable {
    case unified(UnifiedDiffDisplaySnapshot)
    case split(SplitDiffDisplaySnapshot)

    var actualHighlightedLineCount: Int {
        switch self {
        case .unified(let snapshot):
            snapshot.actualHighlightedLineCount
        case .split(let snapshot):
            snapshot.actualHighlightedLineCount
        }
    }

    var loadingLineCount: Int {
        switch self {
        case .unified(let snapshot):
            snapshot.loadingLineCount
        case .split(let snapshot):
            snapshot.loadingLineCount
        }
    }

    var staleHighlightedLineCount: Int {
        switch self {
        case .unified(let snapshot):
            snapshot.staleHighlightedLineCount
        case .split(let snapshot):
            snapshot.staleHighlightedLineCount
        }
    }

    var allVisibleSyntaxLinesActual: Bool {
        switch self {
        case .unified(let snapshot):
            snapshot.allVisibleSyntaxLinesActual
        case .split(let snapshot):
            snapshot.allVisibleSyntaxLinesActual
        }
    }
}

struct DiffDisplaySnapshotRequest: Sendable {
    let layout: DiffRenderLayout
    let visibleRowRange: ClosedRange<Int>
    let syntaxHighlightingEnabled: Bool
    let renderContext: DiffDisplayRenderContext
    let baseSyntaxSnapshot: SyntaxSnapshot?
    let modifiedSyntaxSnapshot: SyntaxSnapshot?
    let baseSemanticOverlaySnapshot: SemanticOverlaySnapshot?
    let modifiedSemanticOverlaySnapshot: SemanticOverlaySnapshot?
}

struct DiffDisplayRenderContext: Sendable {
    let themeVersion: Int
    let metrics: EditorMetrics
    let diffTheme: DiffTheme
}

private struct DiffContentResolutionRequest: Sendable {
    let text: String
    let wordChanges: [DiffWordChange]?
    let segment: DiffHighlightSegment?
    let syntaxHighlightingEnabled: Bool
    let defaultForeground: SIMD4<Float>
    let defaultBackground: SIMD4<Float>
    let placeholderBackground: SIMD4<Float>
    let addedWordBackground: SIMD4<Float>
    let removedWordBackground: SIMD4<Float>
    let baseSyntaxSnapshot: SyntaxSnapshot?
    let modifiedSyntaxSnapshot: SyntaxSnapshot?
    let baseSemanticOverlaySnapshot: SemanticOverlaySnapshot?
    let modifiedSemanticOverlaySnapshot: SemanticOverlaySnapshot?
}

private struct DiffSplitSideRequest: Sendable {
    let side: SplitDiffSide
    let syntaxHighlightingEnabled: Bool
    let diffTheme: DiffTheme
    let baseSyntaxSnapshot: SyntaxSnapshot?
    let modifiedSyntaxSnapshot: SyntaxSnapshot?
    let baseSemanticOverlaySnapshot: SemanticOverlaySnapshot?
    let modifiedSemanticOverlaySnapshot: SemanticOverlaySnapshot?
}

private struct DiffPlainContentStyle: Sendable {
    let foregroundColor: SIMD4<Float>
    let backgroundColor: SIMD4<Float>
    let syntaxStatus: HighlightStatus?
    let addedBackground: SIMD4<Float>
    let removedBackground: SIMD4<Float>
}

@MainActor
final class DiffDisplayModel {
    private struct CacheKey: Hashable {
        let layoutFingerprint: Int
        let visibleRowRange: ClosedRange<Int>
        let syntaxHighlightingEnabled: Bool
            let themeVersion: Int
            let metrics: EditorMetrics
            let diffTheme: DiffTheme
        let baseSyntaxSnapshotRevision: UInt64
        let modifiedSyntaxSnapshotRevision: UInt64
        let baseSemanticOverlayRevision: Int
        let modifiedSemanticOverlayRevision: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(layoutFingerprint)
            hasher.combine(visibleRowRange.lowerBound)
            hasher.combine(visibleRowRange.upperBound)
            hasher.combine(syntaxHighlightingEnabled)
            hasher.combine(themeVersion)
            hasher.combine(metrics.fontName)
            hasher.combine(metrics.fontSize)
            hasher.combine(metrics.cellWidth)
            hasher.combine(metrics.lineHeight)
            hasher.combine(metrics.baseline)
            hasher.combine(metrics.gutterWidth)
            hasher.combine(diffTheme.background.x)
            hasher.combine(diffTheme.background.y)
            hasher.combine(diffTheme.background.z)
            hasher.combine(diffTheme.background.w)
            hasher.combine(diffTheme.foreground.x)
            hasher.combine(diffTheme.foreground.y)
            hasher.combine(diffTheme.foreground.z)
            hasher.combine(diffTheme.foreground.w)
            hasher.combine(baseSyntaxSnapshotRevision)
            hasher.combine(modifiedSyntaxSnapshotRevision)
            hasher.combine(baseSemanticOverlayRevision)
            hasher.combine(modifiedSemanticOverlayRevision)
        }
    }

    private static let sharedCacheLimit = 24
    private static var sharedSnapshots: [CacheKey: DiffDisplaySnapshot] = [:]
    private static var sharedSnapshotOrder: [CacheKey] = []

    private var cachedKey: CacheKey?
    private var cachedSnapshot: DiffDisplaySnapshot?
    private(set) var lastSnapshotUsedSharedCache = false

    func snapshot(_ request: DiffDisplaySnapshotRequest) -> DiffDisplaySnapshot {
        _ = SyntaxRuntimeDiagnostics.recordDisplayPreparationDuringRender(
            operation: "DiffDisplayModel.snapshot",
            metadata: "visibleRows=\(request.visibleRowRange.lowerBound)...\(request.visibleRowRange.upperBound)"
        )
        let cacheKey = CacheKey(
            layoutFingerprint: layoutFingerprint(
                for: request.layout,
                visibleRowRange: request.visibleRowRange
            ),
            visibleRowRange: request.visibleRowRange,
            syntaxHighlightingEnabled: request.syntaxHighlightingEnabled,
            themeVersion: request.renderContext.themeVersion,
            metrics: request.renderContext.metrics,
            diffTheme: request.renderContext.diffTheme,
            baseSyntaxSnapshotRevision: request.baseSyntaxSnapshot?.revision ?? 0,
            modifiedSyntaxSnapshotRevision: request.modifiedSyntaxSnapshot?.revision ?? 0,
            baseSemanticOverlayRevision: request.baseSemanticOverlaySnapshot?.revision ?? 0,
            modifiedSemanticOverlayRevision: request.modifiedSemanticOverlaySnapshot?.revision ?? 0
        )

        if cachedKey == cacheKey, let cachedSnapshot {
            lastSnapshotUsedSharedCache = false
            return cachedSnapshot
        }
        if let sharedSnapshot = Self.sharedSnapshots[cacheKey] {
            cachedKey = cacheKey
            cachedSnapshot = sharedSnapshot
            lastSnapshotUsedSharedCache = true
            return sharedSnapshot
        }

        let snapshot = buildSnapshot(request)
        cachedKey = cacheKey
        cachedSnapshot = snapshot
        lastSnapshotUsedSharedCache = false
        Self.storeSharedSnapshot(snapshot, for: cacheKey)
        return snapshot
    }

    func reset() {
        cachedKey = nil
        cachedSnapshot = nil
        lastSnapshotUsedSharedCache = false
    }

    static func resetSharedCacheForTesting() {
        sharedSnapshots.removeAll()
        sharedSnapshotOrder.removeAll()
    }

    private func buildSnapshot(_ request: DiffDisplaySnapshotRequest) -> DiffDisplaySnapshot {
        switch request.layout {
        case .unified(let unified):
            return .unified(
                buildUnifiedSnapshot(
                    layout: unified,
                    request: request
                )
            )
        case .split(let split):
            return .split(
                buildSplitSnapshot(
                    layout: split,
                    request: request
                )
            )
        }
    }

    private func buildUnifiedSnapshot(
        layout: UnifiedDiffLayout,
        request: DiffDisplaySnapshotRequest
    ) -> UnifiedDiffDisplaySnapshot {
        let rows = Array(layout.rows[request.visibleRowRange]).enumerated().map { offset, row in
            makeUnifiedRow(
                row,
                rowIndex: request.visibleRowRange.lowerBound + offset,
                request: request
            )
        }

        return UnifiedDiffDisplaySnapshot(
            visibleRowRange: request.visibleRowRange,
            rows: rows,
            visibleSyntaxLineCount: rows.count(where: \.content.isSyntaxTracked),
            actualHighlightedLineCount: rows.count(where: \.content.countsAsActualHighlight),
            staleHighlightedLineCount: rows.count { $0.content.syntaxStatus == .stale }
        )
    }

    private func buildSplitSnapshot(
        layout: SplitDiffLayout,
        request: DiffDisplaySnapshotRequest
    ) -> SplitDiffDisplaySnapshot {
        let headerTextByRowIndex = Dictionary(
            uniqueKeysWithValues: layout.hunkHeaders.map { header in
                (
                    header.rowIndex,
                    makePlainPacket(
                        text: "@@ -\(header.oldStart),\(header.oldCount) +\(header.newStart),\(header.newCount) @@",
                        foregroundColor: request.renderContext.diffTheme.hunkHeaderForeground,
                        backgroundColor: .zero,
                        flags: 0
                    )
                )
            }
        )

        let rows = Array(layout.rows[request.visibleRowRange]).enumerated().map { offset, row in
            makeSplitRow(
                row,
                rowIndex: request.visibleRowRange.lowerBound + offset,
                headerPacket: headerTextByRowIndex[request.visibleRowRange.lowerBound + offset],
                request: request
            )
        }

        return SplitDiffDisplaySnapshot(
            visibleRowRange: request.visibleRowRange,
            rows: rows,
            visibleSyntaxLineCount: countTrackedSplitLines(in: rows),
            actualHighlightedLineCount: countActualSplitLines(in: rows),
            staleHighlightedLineCount: countStaleSplitLines(in: rows)
        )
    }

    private func makeUnifiedRow(
        _ row: UnifiedDiffRow,
        rowIndex: Int,
        request: DiffDisplaySnapshotRequest
    ) -> VisibleUnifiedDiffDisplayRow {
        let diffTheme = request.renderContext.diffTheme
        return VisibleUnifiedDiffDisplayRow(
            rowIndex: rowIndex,
            id: row.id,
            kind: row.kind,
            lineType: row.lineType,
            oldLineNumberPacket: row.oldLineNumber.map {
                makePlainPacket(
                    text: String($0),
                    foregroundColor: diffTheme.lineNumber,
                    backgroundColor: gutterBackground(for: row.lineType, theme: diffTheme),
                    flags: 0
                )
            },
            newLineNumberPacket: row.newLineNumber.map {
                makePlainPacket(
                    text: String($0),
                    foregroundColor: diffTheme.lineNumber,
                    backgroundColor: gutterBackground(for: row.lineType, theme: diffTheme),
                    flags: 0
                )
            },
            prefixPacket: configurationPrefixPacket(for: row.lineType, theme: diffTheme),
            content: resolvedContent(
                DiffContentResolutionRequest(
                    text: row.content,
                    wordChanges: row.wordChanges,
                    segment: row.highlightSegment,
                    syntaxHighlightingEnabled: request.syntaxHighlightingEnabled,
                    defaultForeground: row.kind == .hunkHeader
                        ? diffTheme.hunkHeaderForeground
                        : diffTheme.foreground,
                    defaultBackground: SIMD4<Float>(repeating: 0),
                    placeholderBackground: placeholderBackground(for: diffTheme),
                    addedWordBackground: diffTheme.addedTextBackground,
                    removedWordBackground: diffTheme.removedTextBackground,
                    baseSyntaxSnapshot: request.baseSyntaxSnapshot,
                    modifiedSyntaxSnapshot: request.modifiedSyntaxSnapshot,
                    baseSemanticOverlaySnapshot: request.baseSemanticOverlaySnapshot,
                    modifiedSemanticOverlaySnapshot: request.modifiedSemanticOverlaySnapshot
                )
            )
        )
    }

    private func makeSplitRow(
        _ row: SplitDiffRow,
        rowIndex: Int,
        headerPacket: TextRenderPacket?,
        request: DiffDisplaySnapshotRequest
    ) -> VisibleSplitDiffDisplayRow {
        VisibleSplitDiffDisplayRow(
            rowIndex: rowIndex,
            id: row.id,
            kind: row.kind,
            headerPacket: row.kind == .hunkHeader ? headerPacket : nil,
            left: row.left.map {
                splitSide(
                    DiffSplitSideRequest(
                        side: $0,
                        syntaxHighlightingEnabled: request.syntaxHighlightingEnabled,
                        diffTheme: request.renderContext.diffTheme,
                        baseSyntaxSnapshot: request.baseSyntaxSnapshot,
                        modifiedSyntaxSnapshot: request.modifiedSyntaxSnapshot,
                        baseSemanticOverlaySnapshot: request.baseSemanticOverlaySnapshot,
                        modifiedSemanticOverlaySnapshot: request.modifiedSemanticOverlaySnapshot
                    )
                )
            },
            right: row.right.map {
                splitSide(
                    DiffSplitSideRequest(
                        side: $0,
                        syntaxHighlightingEnabled: request.syntaxHighlightingEnabled,
                        diffTheme: request.renderContext.diffTheme,
                        baseSyntaxSnapshot: request.baseSyntaxSnapshot,
                        modifiedSyntaxSnapshot: request.modifiedSyntaxSnapshot,
                        baseSemanticOverlaySnapshot: request.baseSemanticOverlaySnapshot,
                        modifiedSemanticOverlaySnapshot: request.modifiedSemanticOverlaySnapshot
                    )
                )
            }
        )
    }

    private func splitSide(_ request: DiffSplitSideRequest) -> SplitDiffDisplaySide {
        let diffTheme = request.diffTheme
        return SplitDiffDisplaySide(
            lineType: request.side.lineType,
            lineNumberPacket: request.side.lineNumber.map {
                makePlainPacket(
                    text: String($0),
                    foregroundColor: diffTheme.lineNumber,
                    backgroundColor: gutterBackground(for: request.side.lineType, theme: diffTheme),
                    flags: 0
                )
            },
            content: resolvedContent(
                DiffContentResolutionRequest(
                    text: request.side.content,
                    wordChanges: request.side.wordChanges,
                    segment: request.side.highlightSegment,
                    syntaxHighlightingEnabled: request.syntaxHighlightingEnabled,
                    defaultForeground: diffTheme.foreground,
                    defaultBackground: SIMD4<Float>(repeating: 0),
                    placeholderBackground: placeholderBackground(for: diffTheme),
                    addedWordBackground: diffTheme.addedTextBackground,
                    removedWordBackground: diffTheme.removedTextBackground,
                    baseSyntaxSnapshot: request.baseSyntaxSnapshot,
                    modifiedSyntaxSnapshot: request.modifiedSyntaxSnapshot,
                    baseSemanticOverlaySnapshot: request.baseSemanticOverlaySnapshot,
                    modifiedSemanticOverlaySnapshot: request.modifiedSemanticOverlaySnapshot
                )
            )
        )
    }

    private func resolvedContent(_ request: DiffContentResolutionRequest) -> DiffDisplayText {
        guard request.syntaxHighlightingEnabled, let segment = request.segment else {
            return makePlainContent(
                text: request.text,
                wordChanges: request.wordChanges,
                style: plainContentStyle(for: request)
            )
        }

        guard let resolvedSyntax = resolvedSyntaxContext(for: segment, request: request) else {
            return makePlaceholderContent(text: request.text, wordChanges: request.wordChanges, request: request)
        }

        guard resolvedSyntax.line.status.isRenderable else {
            return makePlaceholderContent(text: request.text, wordChanges: request.wordChanges, request: request)
        }

        guard segment.utf16Range.lowerBound <= segment.utf16Range.upperBound,
              segment.utf16Range.upperBound <= resolvedSyntax.line.text.utf16.count else {
            assertionFailure("Invalid diff highlight segment range \(segment.utf16Range)")
            return makePlaceholderContent(text: request.text, wordChanges: request.wordChanges, request: request)
        }

        let slicedTokens = slicedTokens(
            from: resolvedSyntax.line,
            visibleUTF16Range: segment.utf16Range
        )

        if !request.text.isEmpty, slicedTokens.isEmpty {
            assertionFailure("Diff segment tokens were empty for non-empty visible text")
        }

        return makeResolvedSyntaxContent(
            request: request,
            segment: segment,
            resolvedSyntax: resolvedSyntax,
            slicedTokens: slicedTokens
        )
    }

    private func plainContentStyle(for request: DiffContentResolutionRequest) -> DiffPlainContentStyle {
        DiffPlainContentStyle(
            foregroundColor: request.defaultForeground,
            backgroundColor: request.defaultBackground,
            syntaxStatus: nil,
            addedBackground: request.addedWordBackground,
            removedBackground: request.removedWordBackground
        )
    }

    private func makeResolvedSyntaxContent(
        request: DiffContentResolutionRequest,
        segment: DiffHighlightSegment,
        resolvedSyntax: (line: SyntaxHighlightedLine, semanticOverlaySnapshot: SemanticOverlaySnapshot?),
        slicedTokens: [SyntaxHighlightToken]
    ) -> DiffDisplayText {
        DiffDisplayText(
            packet: applySemanticOverlay(
                resolvedSyntax.semanticOverlaySnapshot?.line(segment.sourceLineIndex),
                visibleUTF16Range: segment.utf16Range,
                to: makeSyntaxPacket(
                    text: request.text,
                    tokens: slicedTokens,
                    defaultBackground: request.defaultBackground,
                    wordChanges: request.wordChanges,
                    addedWordBackground: request.addedWordBackground,
                    removedWordBackground: request.removedWordBackground
                ),
                text: request.text
            ),
            syntaxStatus: resolvedSyntax.line.status
        )
    }

    private func makePlainContent(
        text: String,
        wordChanges: [DiffWordChange]?,
        style: DiffPlainContentStyle
    ) -> DiffDisplayText {
        DiffDisplayText(
            packet: makePlainPacket(
                text: text,
                foregroundColor: style.foregroundColor,
                backgroundColor: style.backgroundColor,
                flags: 0,
                wordChanges: wordChanges,
                addedBackground: style.addedBackground,
                removedBackground: style.removedBackground
            ),
            syntaxStatus: style.syntaxStatus
        )
    }

    private func makePlaceholderContent(
        text: String,
        wordChanges: [DiffWordChange]?,
        request: DiffContentResolutionRequest
    ) -> DiffDisplayText {
        makePlainContent(
            text: text,
            wordChanges: wordChanges,
            style: DiffPlainContentStyle(
                foregroundColor: request.defaultForeground,
                backgroundColor: request.defaultBackground,
                syntaxStatus: nil,
                addedBackground: request.addedWordBackground,
                removedBackground: request.removedWordBackground
            )
        )
    }

    private func resolvedSyntaxContext(
        for segment: DiffHighlightSegment,
        request: DiffContentResolutionRequest
    ) -> (line: SyntaxHighlightedLine, semanticOverlaySnapshot: SemanticOverlaySnapshot?)? {
        let syntaxSnapshot = switch segment.side {
        case .base:
            request.baseSyntaxSnapshot
        case .modified:
            request.modifiedSyntaxSnapshot
        }
        let semanticOverlaySnapshot = switch segment.side {
        case .base:
            request.baseSemanticOverlaySnapshot
        case .modified:
            request.modifiedSemanticOverlaySnapshot
        }
        guard let syntaxSnapshot,
              let line = syntaxSnapshot.line(segment.sourceLineIndex) else {
            return nil
        }
        return (line, semanticOverlaySnapshot)
    }

    private func slicedTokens(
        from line: SyntaxHighlightedLine,
        visibleUTF16Range: Range<Int>
    ) -> [SyntaxHighlightToken] {
        line.tokens.compactMap { token -> SyntaxHighlightToken? in
            guard token.range.overlaps(visibleUTF16Range) else { return nil }
            let lower = max(token.range.lowerBound, visibleUTF16Range.lowerBound) - visibleUTF16Range.lowerBound
            let upper = min(token.range.upperBound, visibleUTF16Range.upperBound) - visibleUTF16Range.lowerBound
            guard lower < upper else { return nil }
            return SyntaxHighlightToken(
                range: lower..<upper,
                foregroundColor: token.foregroundColor,
                backgroundColor: token.backgroundColor,
                fontStyle: token.fontStyle
            )
        }
    }

    private func countTrackedSplitLines(in rows: [VisibleSplitDiffDisplayRow]) -> Int {
        rows.reduce(into: 0) { count, row in
            if row.left?.content.isSyntaxTracked == true { count += 1 }
            if row.right?.content.isSyntaxTracked == true { count += 1 }
        }
    }

    private func countActualSplitLines(in rows: [VisibleSplitDiffDisplayRow]) -> Int {
        rows.reduce(into: 0) { count, row in
            if row.left?.content.countsAsActualHighlight == true { count += 1 }
            if row.right?.content.countsAsActualHighlight == true { count += 1 }
        }
    }

    private func countStaleSplitLines(in rows: [VisibleSplitDiffDisplayRow]) -> Int {
        rows.reduce(into: 0) { count, row in
            if row.left?.content.syntaxStatus == .stale { count += 1 }
            if row.right?.content.syntaxStatus == .stale { count += 1 }
        }
    }

    private func makePlainPacket(
        text: String,
        foregroundColor: SIMD4<Float>,
        backgroundColor: SIMD4<Float>,
        flags: UInt32,
        wordChanges: [DiffWordChange]? = nil,
        addedBackground: SIMD4<Float>? = nil,
        removedBackground: SIMD4<Float>? = nil
    ) -> TextRenderPacket {
        let cells = Array(text).enumerated().map { index, char in
            TextRenderCell(
                glyph: char,
                foregroundColor: foregroundColor,
                backgroundColor: backgroundForWordChange(
                    at: index,
                    wordChanges: wordChanges,
                    defaultBackground: backgroundColor,
                    addedBackground: addedBackground,
                    removedBackground: removedBackground
                ),
                flags: flags
            )
        }
        return TextRenderPacket(cells: cells)
    }

    private func makeSyntaxPacket(
        text: String,
        tokens: [SyntaxHighlightToken],
        defaultBackground: SIMD4<Float>,
        wordChanges: [DiffWordChange]?,
        addedWordBackground: SIMD4<Float>,
        removedWordBackground: SIMD4<Float>
    ) -> TextRenderPacket {
        var cells: [TextRenderCell] = []
        cells.reserveCapacity(max(1, text.count))
        var charOffset = 0

        for token in tokens {
            let tokenText = textForToken(token, in: text)
            let flags = tokenFlags(token)
            let foregroundColor = hexToLinearColor(token.foregroundColor)
            let tokenBackground = token.backgroundColor.map { hexToLinearColor($0) } ?? defaultBackground

            for char in tokenText {
                cells.append(
                    TextRenderCell(
                        glyph: char,
                        foregroundColor: foregroundColor,
                        backgroundColor: backgroundForWordChange(
                            at: charOffset,
                            wordChanges: wordChanges,
                            defaultBackground: tokenBackground,
                            addedBackground: addedWordBackground,
                            removedBackground: removedWordBackground
                        ),
                        flags: flags
                    )
                )
                charOffset += 1
            }
        }

        return TextRenderPacket(cells: cells)
    }

    private func backgroundForWordChange(
        at offset: Int,
        wordChanges: [DiffWordChange]?,
        defaultBackground: SIMD4<Float>,
        addedBackground: SIMD4<Float>?,
        removedBackground: SIMD4<Float>?
    ) -> SIMD4<Float> {
        guard let wordChanges else { return defaultBackground }
        for change in wordChanges where change.range.contains(offset) {
            switch change.type {
            case .added:
                return addedBackground ?? defaultBackground
            case .removed:
                return removedBackground ?? defaultBackground
            case .unchanged:
                return defaultBackground
            }
        }
        return defaultBackground
    }

    private func textForToken(_ token: SyntaxHighlightToken, in text: String) -> String {
        let tokenStart = token.range.lowerBound
        let tokenEnd = min(token.range.upperBound, text.utf16.count)
        let startIdx = text.utf16Index(at: tokenStart)
        let endIdx = text.utf16Index(at: tokenEnd)
        return String(text[startIdx..<endIdx])
    }

    private func tokenFlags(_ token: SyntaxHighlightToken) -> UInt32 {
        var flags: UInt32 = 0
        if token.fontStyle.contains(.bold) { flags |= EditorCellFlags.bold.rawValue }
        if token.fontStyle.contains(.italic) { flags |= EditorCellFlags.italic.rawValue }
        if token.fontStyle.contains(.underline) { flags |= EditorCellFlags.underline.rawValue }
        return flags
    }

    private func applySemanticOverlay(
        _ semanticOverlayLine: SemanticOverlayLine?,
        visibleUTF16Range: Range<Int>,
        to packet: TextRenderPacket,
        text: String
    ) -> TextRenderPacket {
        guard let semanticOverlayLine, packet.isEmpty == false else { return packet }
        var cells = packet.cells

        for token in semanticOverlayLine.tokens {
            guard token.range.overlaps(visibleUTF16Range) else { continue }
            let localLower = max(token.range.lowerBound, visibleUTF16Range.lowerBound) - visibleUTF16Range.lowerBound
            let localUpper = min(token.range.upperBound, visibleUTF16Range.upperBound) - visibleUTF16Range.lowerBound
            guard let characterRange = characterRange(forUTF16Range: localLower..<localUpper, in: text) else {
                continue
            }

            for index in characterRange {
                guard cells.indices.contains(index) else { continue }
                var cell = cells[index]
                if let foregroundColor = token.style.foregroundColor {
                    cell = TextRenderCell(
                        glyph: cell.glyph,
                        foregroundColor: hexToLinearColor(foregroundColor),
                        backgroundColor: cell.backgroundColor,
                        flags: cell.flags
                    )
                }
                if let backgroundColor = token.style.backgroundColor {
                    cell = TextRenderCell(
                        glyph: cell.glyph,
                        foregroundColor: cell.foregroundColor,
                        backgroundColor: hexToLinearColor(backgroundColor),
                        flags: cell.flags
                    )
                }
                if let fontStyle = token.style.fontStyle {
                    cell = TextRenderCell(
                        glyph: cell.glyph,
                        foregroundColor: cell.foregroundColor,
                        backgroundColor: cell.backgroundColor,
                        flags: cell.flags | tokenFlags(fontStyle)
                    )
                }
                cells[index] = cell
            }
        }

        return TextRenderPacket(cells: cells)
    }

    private func characterRange(
        forUTF16Range utf16Range: Range<Int>,
        in text: String
    ) -> Range<Int>? {
        guard utf16Range.lowerBound < utf16Range.upperBound else { return nil }

        var utf16Offset = 0
        var lowerCharacterIndex: Int?
        var upperCharacterIndex: Int?

        for (characterIndex, character) in text.enumerated() {
            let nextUTF16Offset = utf16Offset + String(character).utf16.count
            if lowerCharacterIndex == nil, utf16Range.lowerBound < nextUTF16Offset {
                lowerCharacterIndex = characterIndex
            }
            if utf16Range.upperBound <= nextUTF16Offset {
                upperCharacterIndex = characterIndex + 1
                break
            }
            utf16Offset = nextUTF16Offset
        }

        if lowerCharacterIndex == nil, utf16Range.lowerBound == text.utf16.count {
            lowerCharacterIndex = text.count
        }
        if upperCharacterIndex == nil, utf16Range.upperBound == text.utf16.count {
            upperCharacterIndex = text.count
        }

        guard let lowerCharacterIndex, let upperCharacterIndex, lowerCharacterIndex < upperCharacterIndex else {
            return nil
        }
        return lowerCharacterIndex..<upperCharacterIndex
    }

    private func tokenFlags(_ fontStyle: FontStyle) -> UInt32 {
        var flags: UInt32 = 0
        if fontStyle.contains(.bold) { flags |= EditorCellFlags.bold.rawValue }
        if fontStyle.contains(.italic) { flags |= EditorCellFlags.italic.rawValue }
        if fontStyle.contains(.underline) { flags |= EditorCellFlags.underline.rawValue }
        return flags
    }

    private func configurationPrefixPacket(
        for lineType: DiffLine.LineType,
        theme: DiffTheme
    ) -> TextRenderPacket? {
        let prefix = prefixCharacter(for: lineType, isNoNewline: lineType == .noNewline)
        guard !prefix.isEmpty else { return nil }
        return makePlainPacket(
            text: prefix,
            foregroundColor: prefixColor(for: lineType, theme: theme),
            backgroundColor: .zero,
            flags: 0
        )
    }

    private func prefixCharacter(for type: DiffLine.LineType, isNoNewline: Bool) -> String {
        if isNoNewline { return "\\" }
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        case .header: return ""
        case .noNewline: return "\\"
        }
    }

    private func prefixColor(for type: DiffLine.LineType, theme: DiffTheme) -> SIMD4<Float> {
        switch type {
        case .added:
            return theme.addedForeground
        case .removed:
            return theme.removedForeground
        default:
            return theme.lineNumber
        }
    }

    private func gutterBackground(
        for type: DiffLine.LineType,
        theme: DiffTheme
    ) -> SIMD4<Float> {
        switch type {
        case .added:
            return theme.addedGutterBackground
        case .removed:
            return theme.removedGutterBackground
        default:
            return theme.gutterBackground
        }
    }

    private func placeholderBackground(for theme: DiffTheme) -> SIMD4<Float> {
        SIMD4(theme.lineNumber.x, theme.lineNumber.y, theme.lineNumber.z, 0.12)
    }

    private func layoutFingerprint(
        for layout: DiffRenderLayout,
        visibleRowRange: ClosedRange<Int>
    ) -> Int {
        switch layout {
        case .unified(let unified):
            return visibleLayoutFingerprint(
                rowIDs: Array(unified.rows[visibleRowRange]).map(\.id),
                contentWidth: unified.contentSize.width,
                sourceVersion: unified.sourceDocuments.version.rawValue,
                mode: "unified"
            )
        case .split(let split):
            return visibleLayoutFingerprint(
                rowIDs: Array(split.rows[visibleRowRange]).map(\.id),
                contentWidth: split.contentSize.width,
                sourceVersion: split.sourceDocuments.version.rawValue,
                mode: "split"
            )
        }
    }

    private func visibleLayoutFingerprint(
        rowIDs: [String],
        contentWidth: CGFloat,
        sourceVersion: Int,
        mode: String
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(mode)
        hasher.combine(sourceVersion)
        hasher.combine(contentWidth)
        hasher.combine(rowIDs.count)
        for rowID in rowIDs {
            hasher.combine(rowID)
        }
        return hasher.finalize()
    }

    private static func storeSharedSnapshot(
        _ snapshot: DiffDisplaySnapshot,
        for key: CacheKey
    ) {
        sharedSnapshots[key] = snapshot
        sharedSnapshotOrder.removeAll { $0 == key }
        sharedSnapshotOrder.append(key)
        while sharedSnapshotOrder.count > sharedCacheLimit {
            let removedKey = sharedSnapshotOrder.removeFirst()
            sharedSnapshots.removeValue(forKey: removedKey)
        }
    }
}
// swiftlint:enable file_length type_body_length
