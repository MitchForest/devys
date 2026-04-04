// periphery:ignore:all - render snapshot models are consumed by Metal rendering and tests
import Foundation
import Rendering
import Syntax
import Text

struct EditorDisplayRow: Sendable, Equatable {
    let lineIndex: Int
    let text: String
    let highlightedLine: SyntaxHighlightedLine?
    let lineNumberPacket: TextRenderPacket
    let contentPacket: TextRenderPacket
}

struct EditorDisplaySnapshot: Sendable, Equatable {
    struct CacheKey: Sendable, Hashable {
        let documentReopenIdentity: EditorDocumentReopenIdentity
        let documentVersion: DocumentVersion
        let visibleRange: Range<Int>
        let themeVersion: Int
        let metrics: EditorMetrics
        let lineNumberColor: SIMD4<Float>
        let textColor: SIMD4<Float>
        let backgroundColor: SIMD4<Float>
        let syntaxSnapshotRevision: UInt64
        let semanticOverlayRevision: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(documentReopenIdentity)
            hasher.combine(documentVersion)
            hasher.combine(visibleRange.lowerBound)
            hasher.combine(visibleRange.upperBound)
            hasher.combine(themeVersion)
            hasher.combine(metrics.fontName)
            hasher.combine(metrics.fontSize)
            hasher.combine(metrics.cellWidth)
            hasher.combine(metrics.lineHeight)
            hasher.combine(metrics.baseline)
            hasher.combine(metrics.gutterWidth)
            hasher.combine(lineNumberColor.x)
            hasher.combine(lineNumberColor.y)
            hasher.combine(lineNumberColor.z)
            hasher.combine(lineNumberColor.w)
            hasher.combine(textColor.x)
            hasher.combine(textColor.y)
            hasher.combine(textColor.z)
            hasher.combine(textColor.w)
            hasher.combine(backgroundColor.x)
            hasher.combine(backgroundColor.y)
            hasher.combine(backgroundColor.z)
            hasher.combine(backgroundColor.w)
            hasher.combine(syntaxSnapshotRevision)
            hasher.combine(semanticOverlayRevision)
        }
    }

    let documentVersion: DocumentVersion
    let visibleRange: Range<Int>
    let visibleRows: [EditorDisplayRow]
    let cacheKey: CacheKey

    static let empty = EditorDisplaySnapshot(
        documentVersion: DocumentVersion(),
        visibleRange: 0..<0,
        visibleRows: [],
        cacheKey: CacheKey(
            documentReopenIdentity: .empty,
            documentVersion: DocumentVersion(),
            visibleRange: 0..<0,
            themeVersion: 0,
            metrics: EditorMetrics.measure(fontSize: 12),
            lineNumberColor: .zero,
            textColor: .zero,
            backgroundColor: .zero,
            syntaxSnapshotRevision: 0,
            semanticOverlayRevision: 0
        )
    )

    var actualHighlightedLineCount: Int {
        visibleRows.reduce(into: 0) { count, row in
            if row.highlightedLine?.status.countsAsActual == true {
                count += 1
            }
        }
    }
}

struct EditorDisplaySnapshotRequest: Sendable {
    let documentReopenIdentity: EditorDocumentReopenIdentity
    let documentSnapshot: DocumentSnapshot
    let syntaxSnapshot: SyntaxSnapshot?
    let semanticOverlaySnapshot: SemanticOverlaySnapshot?
    let visibleRange: Range<Int>
    let renderContext: EditorDisplayRenderContext
}

struct EditorPreviewSnapshotRequest: Sendable {
    let documentReopenIdentity: EditorDocumentReopenIdentity
    let documentVersion: DocumentVersion
    let visibleLines: [LineSlice]
    let visibleRange: Range<Int>
    let renderContext: EditorDisplayRenderContext
}

struct EditorDisplayRenderContext: Sendable {
    let themeVersion: Int
    let metrics: EditorMetrics
    let lineNumberColor: SIMD4<Float>
    let textColor: SIMD4<Float>
    let backgroundColor: SIMD4<Float>
}

@MainActor
final class EditorDisplayModel {
    private static let sharedCacheLimit = 16
    private static var sharedSnapshots: [EditorDisplaySnapshot.CacheKey: EditorDisplaySnapshot] = [:]
    private static var sharedSnapshotOrder: [EditorDisplaySnapshot.CacheKey] = []

    private var cachedSnapshot: EditorDisplaySnapshot = .empty
    private(set) var lastSnapshotUsedSharedCache = false

    func snapshot(_ request: EditorDisplaySnapshotRequest) -> EditorDisplaySnapshot {
        _ = SyntaxRuntimeDiagnostics.recordDisplayPreparationDuringRender(
            operation: "EditorDisplayModel.snapshot",
            metadata: "visibleRange=\(request.visibleRange.lowerBound)..<\(request.visibleRange.upperBound)"
        )
        let cacheKey = makeCacheKey(for: request)
        if let cached = cachedSnapshotIfAvailable(for: cacheKey) {
            return cached
        }

        let visibleRows = buildRows(for: request)
        return storeSnapshot(
            documentVersion: request.documentSnapshot.version,
            visibleRange: request.visibleRange,
            visibleRows: visibleRows,
            cacheKey: cacheKey
        )
    }

    func previewSnapshot(_ request: EditorPreviewSnapshotRequest) -> EditorDisplaySnapshot {
        let cacheKey = makeCacheKey(for: request)
        if let cached = cachedSnapshotIfAvailable(for: cacheKey) {
            return cached
        }

        let visibleRows = buildPreviewRows(for: request)
        return storeSnapshot(
            documentVersion: request.documentVersion,
            visibleRange: request.visibleRange,
            visibleRows: visibleRows,
            cacheKey: cacheKey
        )
    }

    func reset() {
        cachedSnapshot = .empty
        lastSnapshotUsedSharedCache = false
    }

    static func resetSharedCacheForTesting() {
        sharedSnapshots.removeAll()
        sharedSnapshotOrder.removeAll()
    }

    private func makeCacheKey(for request: EditorDisplaySnapshotRequest) -> EditorDisplaySnapshot.CacheKey {
        EditorDisplaySnapshot.CacheKey(
            documentReopenIdentity: request.documentReopenIdentity,
            documentVersion: request.documentSnapshot.version,
            visibleRange: request.visibleRange,
            themeVersion: request.renderContext.themeVersion,
            metrics: request.renderContext.metrics,
            lineNumberColor: request.renderContext.lineNumberColor,
            textColor: request.renderContext.textColor,
            backgroundColor: request.renderContext.backgroundColor,
            syntaxSnapshotRevision: request.syntaxSnapshot?.revision ?? 0,
            semanticOverlayRevision: request.semanticOverlaySnapshot?.revision ?? 0
        )
    }

    private func makeCacheKey(for request: EditorPreviewSnapshotRequest) -> EditorDisplaySnapshot.CacheKey {
        EditorDisplaySnapshot.CacheKey(
            documentReopenIdentity: request.documentReopenIdentity,
            documentVersion: request.documentVersion,
            visibleRange: request.visibleRange,
            themeVersion: request.renderContext.themeVersion,
            metrics: request.renderContext.metrics,
            lineNumberColor: request.renderContext.lineNumberColor,
            textColor: request.renderContext.textColor,
            backgroundColor: request.renderContext.backgroundColor,
            syntaxSnapshotRevision: 0,
            semanticOverlayRevision: 0
        )
    }

    private func cachedSnapshotIfAvailable(
        for cacheKey: EditorDisplaySnapshot.CacheKey
    ) -> EditorDisplaySnapshot? {
        if cachedSnapshot.cacheKey == cacheKey {
            lastSnapshotUsedSharedCache = false
            return cachedSnapshot
        }
        if let sharedSnapshot = Self.sharedSnapshots[cacheKey] {
            cachedSnapshot = sharedSnapshot
            lastSnapshotUsedSharedCache = true
            return sharedSnapshot
        }
        return nil
    }

    private func buildRows(for request: EditorDisplaySnapshotRequest) -> [EditorDisplayRow] {
        let placeholderBackground = request.renderContext.backgroundColor

        return request.documentSnapshot.lines(in: request.visibleRange).map { lineSlice in
            let highlightedLine = request.syntaxSnapshot?.line(lineSlice.lineIndex)
            let semanticOverlayLine = request.semanticOverlaySnapshot?.line(lineSlice.lineIndex)
            return EditorDisplayRow(
                lineIndex: lineSlice.lineIndex,
                text: lineSlice.text,
                highlightedLine: highlightedLine,
                lineNumberPacket: makeLineNumberPacket(
                    lineIndex: lineSlice.lineIndex,
                    lineNumberColor: request.renderContext.lineNumberColor,
                    backgroundColor: request.renderContext.backgroundColor
                ),
                contentPacket: makeContentPacket(
                    text: lineSlice.text,
                    highlightedLine: highlightedLine,
                    semanticOverlayLine: semanticOverlayLine,
                    defaultForegroundColor: request.renderContext.textColor,
                    backgroundColor: request.renderContext.backgroundColor,
                    placeholderBackground: placeholderBackground
                )
            )
        }
    }

    private func buildPreviewRows(for request: EditorPreviewSnapshotRequest) -> [EditorDisplayRow] {
        request.visibleLines.map { lineSlice in
            EditorDisplayRow(
                lineIndex: lineSlice.lineIndex,
                text: lineSlice.text,
                highlightedLine: nil,
                lineNumberPacket: makeLineNumberPacket(
                    lineIndex: lineSlice.lineIndex,
                    lineNumberColor: request.renderContext.lineNumberColor,
                    backgroundColor: request.renderContext.backgroundColor
                ),
                contentPacket: makeContentPacket(
                    text: lineSlice.text,
                    highlightedLine: nil,
                    semanticOverlayLine: nil,
                    defaultForegroundColor: request.renderContext.textColor,
                    backgroundColor: request.renderContext.backgroundColor,
                    placeholderBackground: request.renderContext.backgroundColor
                )
            )
        }
    }

    private func storeSnapshot(
        documentVersion: DocumentVersion,
        visibleRange: Range<Int>,
        visibleRows: [EditorDisplayRow],
        cacheKey: EditorDisplaySnapshot.CacheKey
    ) -> EditorDisplaySnapshot {
        let snapshot = EditorDisplaySnapshot(
            documentVersion: documentVersion,
            visibleRange: visibleRange,
            visibleRows: visibleRows,
            cacheKey: cacheKey
        )
        cachedSnapshot = snapshot
        lastSnapshotUsedSharedCache = false
        Self.storeSharedSnapshot(snapshot, for: cacheKey)
        return snapshot
    }

    private func makeLineNumberPacket(
        lineIndex: Int,
        lineNumberColor: SIMD4<Float>,
        backgroundColor: SIMD4<Float>
    ) -> TextRenderPacket {
        let numberText = String(lineIndex + 1)
        let cells = numberText.map { char in
            TextRenderCell(
                glyph: char,
                foregroundColor: lineNumberColor,
                backgroundColor: backgroundColor,
                flags: EditorCellFlags.lineNumber.rawValue
            )
        }
        return TextRenderPacket(cells: cells)
    }

    private static func storeSharedSnapshot(
        _ snapshot: EditorDisplaySnapshot,
        for key: EditorDisplaySnapshot.CacheKey
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

private func makeContentPacket(
    text: String,
    highlightedLine: SyntaxHighlightedLine?,
    semanticOverlayLine: SemanticOverlayLine?,
    defaultForegroundColor: SIMD4<Float>,
    backgroundColor: SIMD4<Float>,
    placeholderBackground: SIMD4<Float>
) -> TextRenderPacket {
    guard let highlightedLine else {
        return makePlainTextPacket(
            text: text,
            foregroundColor: defaultForegroundColor,
            backgroundColor: placeholderBackground
        )
    }

    var cells: [TextRenderCell] = []
    cells.reserveCapacity(max(1, text.count))

    for token in highlightedLine.tokens {
        let tokenText = textForToken(token, in: text)
        let flags = tokenFlags(token.fontStyle)
        let foregroundColor = hexToLinearColor(token.foregroundColor)
        let tokenBackground = token.backgroundColor.map { hexToLinearColor($0) } ?? backgroundColor
        for char in tokenText {
            cells.append(
                TextRenderCell(
                    glyph: char,
                    foregroundColor: foregroundColor,
                    backgroundColor: tokenBackground,
                    flags: flags
                )
            )
        }
    }

    return applySemanticOverlay(
        semanticOverlayLine,
        to: TextRenderPacket(cells: cells),
        text: text
    )
}

private func makePlainTextPacket(
    text: String,
    foregroundColor: SIMD4<Float>,
    backgroundColor: SIMD4<Float>
) -> TextRenderPacket {
    var cells = text.map { char in
        TextRenderCell(
            glyph: char,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor
        )
    }
    if cells.isEmpty {
        cells = [
            TextRenderCell(
                glyph: " ",
                foregroundColor: foregroundColor,
                backgroundColor: backgroundColor
            )
        ]
    }
    return TextRenderPacket(cells: cells)
}

private func textForToken(_ token: SyntaxHighlightToken, in text: String) -> String {
    let tokenStart = token.range.lowerBound
    let tokenEnd = min(token.range.upperBound, text.utf16.count)
    let startIdx = text.utf16Index(at: tokenStart)
    let endIdx = text.utf16Index(at: tokenEnd)
    return String(text[startIdx..<endIdx])
}

private func applySemanticOverlay(
    _ semanticOverlayLine: SemanticOverlayLine?,
    to packet: TextRenderPacket,
    text: String
) -> TextRenderPacket {
    guard let semanticOverlayLine, packet.isEmpty == false else { return packet }
    var cells = packet.cells

    for token in semanticOverlayLine.tokens {
        guard let characterRange = characterRange(forUTF16Range: token.range, in: text) else {
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

    guard let lowerCharacterIndex,
          let upperCharacterIndex,
          lowerCharacterIndex < upperCharacterIndex else {
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
