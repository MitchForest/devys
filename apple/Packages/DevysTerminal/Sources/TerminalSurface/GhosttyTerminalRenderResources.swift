// Ported from the reference repo's TerminalSurface metal support
// (P0-014). Platform-neutral renderer resources shared by the macOS
// NSView host and the net-new iOS host: font metrics, grid metrics,
// cursor presentation, packed-color conversion, and the per-device
// pipeline/atlas caches.

import CoreGraphics
import Foundation
import Metal
import MetalKit
import TerminalMetal
import TerminalSurfaceCore
import TerminalVT
import simd

#if os(macOS)
    import AppKit
    private typealias PlatformFont = NSFont
#else
    import UIKit
    private typealias PlatformFont = UIFont
#endif

struct GhosttyTerminalViewCallbacks {
    var onTap: () -> Void = {}
    var onSelectionBegin: (Int, Int) -> Void = { _, _ in }
    var onSelectionMove: (Int, Int) -> Void = { _, _ in }
    var onSelectionEnd: () -> Void = {}
    var onSelectWord: (Int, Int) -> Void = { _, _ in }
    var onClearSelection: () -> Void = {}
    var onScroll: (TerminalSurfaceScrollEvent) -> Void = { _ in }
    var onSurfaceSizeChange: (TerminalSurfacePixelSize) -> Void = { _ in }
    var onInput: (TerminalSurfaceInputCommand) -> Void = { _ in }
    var selectionTextProvider: () -> String? = { nil }
    var onFirstAtlasMutation: () -> Void = {}
    var onFirstFrameCommit: () -> Void = {}
    var onFirstInteractiveFrame: () -> Void = {}
    var onRenderFailure: (String) -> Void = { _ in }
}

struct GhosttyTerminalFontMetrics {
    let fontName: String
    let fontSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat

    static func `default`(fontSize: CGFloat = 13) -> GhosttyTerminalFontMetrics {
        let clampedFontSize = min(max(fontSize, 10), 22)
        let font = PlatformFont(name: "Menlo-Regular", size: clampedFontSize)
            ?? PlatformFont.monospacedSystemFont(ofSize: clampedFontSize, weight: .regular)
        let metrics = measureTerminalFont(font)
        return GhosttyTerminalFontMetrics(
            fontName: font.fontName,
            fontSize: font.pointSize,
            cellWidth: metrics.cellWidth,
            cellHeight: metrics.lineHeight
        )
    }
}

private func measureTerminalFont(_ font: PlatformFont) -> (cellWidth: CGFloat, lineHeight: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let cellWidth = ceil(("W" as NSString).size(withAttributes: attributes).width)
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    return (max(1, cellWidth), max(1, lineHeight))
}

struct GhosttyTerminalGridMetrics {
    let cols: Int
    let rows: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat

    func clampedCell(for point: CGPoint) -> (row: Int, col: Int) {
        let col = max(0, min(cols - 1, Int(floor(point.x / max(cellWidth, 1)))))
        let row = max(0, min(rows - 1, Int(floor(point.y / max(cellHeight, 1)))))
        return (row, col)
    }

    func rect(row: Int, colStart: Int, colEnd: Int) -> CGRect {
        CGRect(
            x: CGFloat(colStart) * cellWidth,
            y: CGFloat(row) * cellHeight,
            width: CGFloat(max(1, colEnd - colStart + 1)) * cellWidth,
            height: cellHeight
        )
    }

    func selectionRects(for range: TerminalSelectionRange?) -> [CGRect] {
        guard let range else { return [] }
        let normalized = normalizedSelectionRange(range)
        let startRow = max(0, min(rows - 1, normalized.start.row))
        let endRow = max(0, min(rows - 1, normalized.end.row))
        guard endRow >= startRow else { return [] }

        let startCol = max(0, min(cols - 1, normalized.start.col))
        let endCol = max(0, min(cols - 1, normalized.end.col))

        var rects: [CGRect] = []
        for row in startRow...endRow {
            let rowStart = row == startRow ? startCol : 0
            let rowEnd = row == endRow ? endCol : cols - 1
            guard rowEnd >= rowStart else { continue }
            rects.append(rect(row: row, colStart: rowStart, colEnd: rowEnd))
        }
        return rects
    }

    func selectionRects(for ranges: [TerminalSelectionRange]) -> [CGRect] {
        ranges.flatMap { selectionRects(for: $0) }
    }

    func overlayCursorRect(for surfaceState: TerminalSurfaceState) -> CGRect? {
        guard surfaceState.cursorVisible, surfaceState.viewportOffset == 0 else { return nil }

        let row = max(0, min(rows - 1, surfaceState.cursor.row))

        switch surfaceState.cursorStyle {
        case .block:
            return nil
        case .hollowBlock:
            guard let col = resolvedVisibleCursorColumn(for: surfaceState) else { return nil }
            return rect(row: row, colStart: col, colEnd: col)
        case .underline:
            guard let col = resolvedVisibleCursorColumn(for: surfaceState) else { return nil }
            let baseRect = rect(row: row, colStart: col, colEnd: col)
            let height = max(2, floor(cellHeight * 0.12))
            return CGRect(
                x: baseRect.minX,
                y: baseRect.maxY - height,
                width: baseRect.width,
                height: height
            )
        case .beam:
            let col = max(0, min(cols, surfaceState.cursor.col))
            let width = max(2, floor(cellWidth * 0.12))
            return CGRect(
                x: CGFloat(col) * cellWidth,
                y: CGFloat(row) * cellHeight,
                width: width,
                height: cellHeight
            )
        }
    }

    private func resolvedVisibleCursorColumn(
        for surfaceState: TerminalSurfaceState
    ) -> Int? {
        var col = surfaceState.cursor.col
        if surfaceState.cursorWideTail {
            col -= 1
        }
        guard col >= 0, col < cols else { return nil }
        return col
    }
}

struct GhosttyBlockCursorPresentation: Equatable {
    let row: Int
    let col: Int
    // The three fields below are read through the synthesized Equatable
    // conformance: `blockCursorRowsNeedingRebuild` compares presentations
    // so a cursor color or shape change re-renders its row.
    // periphery:ignore
    let colorPacked: UInt32?
    // periphery:ignore
    let wideTail: Bool
    // periphery:ignore
    let pendingWrap: Bool
}

struct GhosttyBlockCursorUpdate {
    let presentation: GhosttyBlockCursorPresentation?
    let dirtyRows: Set<Int>
}

func blockCursorPresentation(
    for surfaceState: TerminalSurfaceState,
    cols: Int,
    rows: Int
) -> GhosttyBlockCursorPresentation? {
    guard surfaceState.cursorVisible,
          surfaceState.viewportOffset == 0,
          surfaceState.cursorStyle == .block,
          rows > 0,
          cols > 0
    else {
        return nil
    }

    let row = max(0, min(rows - 1, surfaceState.cursor.row))
    var col = surfaceState.cursor.col
    if surfaceState.cursorWideTail {
        col -= 1
    }
    if surfaceState.cursorPendingWrap {
        col = min(col, cols - 1)
    }
    guard col >= 0, col < cols else { return nil }

    return GhosttyBlockCursorPresentation(
        row: row,
        col: col,
        colorPacked: surfaceState.cursorColorPacked,
        wideTail: surfaceState.cursorWideTail,
        pendingWrap: surfaceState.cursorPendingWrap
    )
}

func blockCursorRowsNeedingRebuild(
    previous: GhosttyBlockCursorPresentation?,
    current: GhosttyBlockCursorPresentation?
) -> Set<Int> {
    guard previous != current else { return [] }

    var rows: Set<Int> = []
    if let previous {
        rows.insert(previous.row)
    }
    if let current {
        rows.insert(current.row)
    }
    return rows
}

func updatedBlockCursorPresentation(
    previous: GhosttyBlockCursorPresentation?,
    surfaceState: TerminalSurfaceState,
    grid: GhosttyTerminalGridMetrics
) -> GhosttyBlockCursorUpdate {
    let presentation = blockCursorPresentation(
        for: surfaceState,
        cols: grid.cols,
        rows: grid.rows
    )
    return GhosttyBlockCursorUpdate(
        presentation: presentation,
        dirtyRows: blockCursorRowsNeedingRebuild(
            previous: previous,
            current: presentation
        )
    )
}

func frameProjectionRowsByIndex(
    _ frameProjection: TerminalFrameProjection
) -> [Int: TerminalProjectedRow] {
    Dictionary(uniqueKeysWithValues: frameProjection.rowsByIndex.map { ($0.index, $0) })
}

func visibleProjectedRows(
    _ frameProjection: TerminalFrameProjection,
    limit rowLimit: Int
) -> [TerminalProjectedRow] {
    frameProjection.rowsByIndex.filter { $0.index < rowLimit }
}

func rows(
    for indexes: Set<Int>,
    in rowsByIndex: [Int: TerminalProjectedRow]
) -> [TerminalProjectedRow] {
    indexes.compactMap { rowsByIndex[$0] }.sorted { $0.index < $1.index }
}

func mergedRows(
    _ primary: [TerminalProjectedRow],
    _ supplemental: [TerminalProjectedRow]
) -> [TerminalProjectedRow] {
    guard !primary.isEmpty else { return supplemental }
    guard !supplemental.isEmpty else { return primary }

    var merged = primary
    var seenIndexes = Set(primary.map(\.index))

    for row in supplemental where seenIndexes.insert(row.index).inserted {
        merged.append(row)
    }

    return merged.sorted { $0.index < $1.index }
}

// swiftlint:disable:next function_parameter_count
func appendOutline(
    to overlayBuffer: TerminalOverlayBuffer,
    for rect: CGRect,
    scaleX: CGFloat,
    scaleY: CGFloat,
    lineWidth: CGFloat,
    color: SIMD4<Float>
) {
    let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lineWidth)
    let bottom = CGRect(x: rect.minX, y: rect.maxY - lineWidth, width: rect.width, height: lineWidth)
    let left = CGRect(x: rect.minX, y: rect.minY, width: lineWidth, height: rect.height)
    let right = CGRect(x: rect.maxX - lineWidth, y: rect.minY, width: lineWidth, height: rect.height)
    for outlineRect in [top, bottom, left, right] {
        overlayBuffer.addQuad(
            x: Float(outlineRect.minX * scaleX),
            y: Float(outlineRect.minY * scaleY),
            width: Float(outlineRect.width * scaleX),
            height: Float(outlineRect.height * scaleY),
            color: color
        )
    }
}

func resolvedBlockCursorCell(
    in row: TerminalProjectedRow,
    surfaceState: TerminalSurfaceState
) -> TerminalProjectedCell? {
    guard let presentation = blockCursorPresentation(
        for: surfaceState,
        cols: row.cells.count,
        rows: max(surfaceState.rows, 1)
    ),
        row.index == presentation.row
    else {
        return nil
    }

    var column = presentation.col
    guard column >= 0, column < row.cells.count else { return nil }

    while column > 0, row.cells[column].isWideContinuation {
        column -= 1
    }

    let cell = row.cells[column]
    return cell.isRenderable ? cell : nil
}

func blockCursorPackedColors(
    for cell: TerminalProjectedCell,
    surfaceState: TerminalSurfaceState,
    appearance: TerminalAppearance
) -> (foregroundPacked: UInt32, backgroundPacked: UInt32) {
    let backgroundPacked = surfaceState.cursorColorPacked ?? appearance.cursorColor.packedRGB
    let backgroundColor = TerminalColor(packedRGB: backgroundPacked)
    let currentForeground = TerminalColor(packedRGB: cell.foregroundPacked)
    let foregroundColor: TerminalColor

    if currentForeground.contrastRatio(with: backgroundColor) >= 4.5 {
        foregroundColor = currentForeground
    } else {
        foregroundColor = backgroundColor.idealTextColor()
    }

    return (
        foregroundPacked: foregroundColor.packedRGB,
        backgroundPacked: backgroundPacked
    )
}

private extension TerminalColor {
    init(packedRGB: UInt32) {
        self.init(
            red: UInt8((packedRGB >> 16) & 0xFF),
            green: UInt8((packedRGB >> 8) & 0xFF),
            blue: UInt8(packedRGB & 0xFF)
        )
    }
}

private struct GhosttyTerminalRendererResourceKey: Hashable {
    // Every field is read through the synthesized Hashable conformance:
    // the fields ARE the per-(device, font, scale) resource-cache key,
    // so dropping one would alias distinct glyph atlases.
    // periphery:ignore
    let deviceIdentifier: ObjectIdentifier
    // periphery:ignore
    let fontName: String
    // periphery:ignore
    let fontSizeMilliPoints: Int
    // periphery:ignore
    let cellWidthMilliPoints: Int
    // periphery:ignore
    let cellHeightMilliPoints: Int
    // periphery:ignore
    let scaleFactorMilliUnits: Int

    init(
        device: any MTLDevice,
        fontMetrics: GhosttyTerminalFontMetrics,
        scaleFactor: CGFloat
    ) {
        self.deviceIdentifier = ObjectIdentifier(device as AnyObject)
        self.fontName = fontMetrics.fontName
        self.fontSizeMilliPoints = Self.quantize(fontMetrics.fontSize)
        self.cellWidthMilliPoints = Self.quantize(fontMetrics.cellWidth)
        self.cellHeightMilliPoints = Self.quantize(fontMetrics.cellHeight)
        self.scaleFactorMilliUnits = Self.quantize(scaleFactor)
    }

    private static func quantize(_ value: CGFloat) -> Int {
        Int((value * 1_000).rounded())
    }
}

final class GhosttyTerminalPipelineCache {
    private static var pipelines: [ObjectIdentifier: TerminalRenderPipeline] = [:]

    static func sharedPipeline(
        device: any MTLDevice
    ) throws -> TerminalRenderPipeline {
        let key = ObjectIdentifier(device as AnyObject)
        if let pipeline = pipelines[key] {
            return pipeline
        }

        let pipeline = try TerminalRenderPipeline(device: device)
        pipelines[key] = pipeline
        return pipeline
    }
}

/// Per-(device, font, scale) render resources reused across host views so
/// repeated pane mounts never re-rasterize the glyph atlas.
final class GhosttyTerminalRendererResourceStore {
    let pipeline: TerminalRenderPipeline
    let atlas: TerminalGlyphAtlas

    private static var resources: [GhosttyTerminalRendererResourceKey: GhosttyTerminalRendererResourceStore] = [:]

    private init(
        pipeline: TerminalRenderPipeline,
        atlas: TerminalGlyphAtlas
    ) {
        self.pipeline = pipeline
        self.atlas = atlas
    }

    static func shared(
        device: any MTLDevice,
        fontMetrics: GhosttyTerminalFontMetrics,
        scaleFactor: CGFloat
    ) throws -> GhosttyTerminalRendererResourceStore {
        let key = GhosttyTerminalRendererResourceKey(
            device: device,
            fontMetrics: fontMetrics,
            scaleFactor: scaleFactor
        )
        if let cached = resources[key] {
            return cached
        }

        let pipeline = try GhosttyTerminalPipelineCache.sharedPipeline(device: device)
        let atlas = TerminalGlyphAtlas(
            device: device,
            fontName: fontMetrics.fontName,
            fontSize: fontMetrics.fontSize,
            cellWidth: Int(ceil(fontMetrics.cellWidth)),
            cellHeight: Int(ceil(fontMetrics.cellHeight)),
            scaleFactor: scaleFactor
        )
        let store = GhosttyTerminalRendererResourceStore(
            pipeline: pipeline,
            atlas: atlas
        )
        resources[key] = store
        return store
    }
}

struct TerminalRenderContext {
    let view: MTKView
    let drawable: any MTLDrawable
    let commandBuffer: any MTLCommandBuffer
    let encoder: any MTLRenderCommandEncoder
}

struct TerminalPreparedFrame {
    let grid: GhosttyTerminalGridMetrics
    let scaleX: CGFloat
    let scaleY: CGFloat
    let cellWidthPx: Float
    let cellHeightPx: Float
}

func linearColor(fromPacked packed: UInt32, alpha: Float = 1) -> SIMD4<Float> {
    let straight = TerminalColor(
        red: UInt8((packed >> 16) & 0xFF),
        green: UInt8((packed >> 8) & 0xFF),
        blue: UInt8(packed & 0xFF)
    )
    .linearRGBA(alpha: 1)
    // Premultiply RGB by alpha so the cell fragment shader's `mix(bg, fg, glyphAlpha)`
    // does the right thing for transparent default-bg cells: when bg.alpha is 0, the
    // bg color contributes nothing to antialiased glyph edges instead of leaking the
    // theme bg color (e.g. white in light mode -> bright halo around black text).
    // For alpha=1 (foreground, opaque ANSI bg, cursor, etc.) this is a no-op.
    return SIMD4<Float>(
        straight.x * alpha,
        straight.y * alpha,
        straight.z * alpha,
        alpha
    )
}

// swiftlint:disable:next function_parameter_count
func terminalCellDescriptor(
    column: Int,
    cellSpan: Int,
    foregroundPacked: UInt32,
    backgroundPacked: UInt32,
    glyph: TerminalGlyphAtlasEntry,
    flags: TerminalCellFlags = [],
    appearance: TerminalAppearance
) -> TerminalCellDescriptor {
    let backgroundAlpha = terminalCellBackgroundAlpha(
        backgroundPacked: backgroundPacked,
        appearance: appearance
    )
    return TerminalCellDescriptor(
        column: column,
        cellSpan: cellSpan,
        foregroundColor: linearColor(fromPacked: foregroundPacked),
        backgroundColor: linearColor(fromPacked: backgroundPacked, alpha: backgroundAlpha),
        glyph: glyph,
        flags: flags
    )
}

func terminalCellBackgroundAlpha(
    backgroundPacked: UInt32,
    appearance: TerminalAppearance
) -> Float {
    backgroundPacked == appearance.background.packedRGB
        ? appearance.backgroundOpacity
        : 1
}
