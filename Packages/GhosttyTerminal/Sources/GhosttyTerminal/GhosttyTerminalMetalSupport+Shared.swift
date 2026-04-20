import CoreGraphics
import GhosttyTerminalCore
import Metal
import MetalKit
import Rendering
import simd

#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
#elseif os(iOS)
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
    var onScroll: (Int) -> Void = { _ in }
    var onViewportSizeChange: (CGSize, Int, Int, Int, Int) -> Void = { _, _, _, _, _ in }
    var onSendText: (String) -> Void = { _ in }
    var onSendSpecialKey: (GhosttyTerminalSpecialKey) -> Void = { _ in }
    var onSendControlCharacter: (Character) -> Void = { _ in }
    var onSendAltText: (String) -> Void = { _ in }
    var onPasteText: (String) -> Void = { _ in }
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

    static func `default`() -> GhosttyTerminalFontMetrics {
        #if os(macOS)
        let font = NSFont(name: "Menlo-Regular", size: 13)
            ?? PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        #else
        let font = UIFont(name: "Menlo-Regular", size: 13)
            ?? PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        #endif
        let metrics = EditorMetrics.measure(fontSize: font.pointSize, fontName: font.fontName)
        return GhosttyTerminalFontMetrics(
            fontName: metrics.fontName,
            fontSize: metrics.fontSize,
            cellWidth: metrics.cellWidth,
            cellHeight: metrics.lineHeight
        )
    }
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

    func selectionRects(for range: GhosttyTerminalSelectionRange?) -> [CGRect] {
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

    func overlayCursorRect(for surfaceState: GhosttyTerminalSurfaceState) -> CGRect? {
        guard surfaceState.cursorVisible, surfaceState.viewportOffset == 0 else { return nil }

        let row = max(0, min(rows - 1, surfaceState.cursor.row))

        switch surfaceState.cursorStyle {
        case .block:
            return nil
        case .hollowBlock:
            guard let col = resolvedVisibleCursorColumn(for: surfaceState) else { return nil }
            let baseRect = rect(row: row, colStart: col, colEnd: col)
            return baseRect
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
        for surfaceState: GhosttyTerminalSurfaceState
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
    let colorPacked: UInt32?
    let wideTail: Bool
    let pendingWrap: Bool

    static func == (
        lhs: GhosttyBlockCursorPresentation,
        rhs: GhosttyBlockCursorPresentation
    ) -> Bool {
        lhs.row == rhs.row &&
            lhs.col == rhs.col &&
            lhs.colorPacked == rhs.colorPacked &&
            lhs.wideTail == rhs.wideTail &&
            lhs.pendingWrap == rhs.pendingWrap
    }
}

struct GhosttyBlockCursorUpdate {
    let presentation: GhosttyBlockCursorPresentation?
    let dirtyRows: Set<Int>
}

func blockCursorPresentation(
    for surfaceState: GhosttyTerminalSurfaceState,
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
    surfaceState: GhosttyTerminalSurfaceState,
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
    _ frameProjection: GhosttyTerminalFrameProjection
) -> [Int: GhosttyTerminalProjectedRow] {
    Dictionary(uniqueKeysWithValues: frameProjection.rowsByIndex.map { ($0.index, $0) })
}

func visibleProjectedRows(
    _ frameProjection: GhosttyTerminalFrameProjection,
    limit rowLimit: Int
) -> [GhosttyTerminalProjectedRow] {
    frameProjection.rowsByIndex.filter { $0.index < rowLimit }
}

func rows(
    for indexes: Set<Int>,
    in rowsByIndex: [Int: GhosttyTerminalProjectedRow]
) -> [GhosttyTerminalProjectedRow] {
    indexes.compactMap { rowsByIndex[$0] }.sorted { $0.index < $1.index }
}

func mergedRows(
    _ primary: [GhosttyTerminalProjectedRow],
    _ supplemental: [GhosttyTerminalProjectedRow]
) -> [GhosttyTerminalProjectedRow] {
    guard !primary.isEmpty else { return supplemental }
    guard !supplemental.isEmpty else { return primary }

    var merged = primary
    var seenIndexes = Set(primary.map(\.index))

    for row in supplemental where seenIndexes.insert(row.index).inserted {
        merged.append(row)
    }

    return merged.sorted { $0.index < $1.index }
}

@MainActor
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
    in row: GhosttyTerminalProjectedRow,
    surfaceState: GhosttyTerminalSurfaceState
) -> GhosttyTerminalProjectedCell? {
    guard let presentation = blockCursorPresentation(
        for: surfaceState,
        cols: row.cells.count,
        rows: max(surfaceState.rows, 1)
    ),
    row.index == presentation.row else {
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
    for cell: GhosttyTerminalProjectedCell,
    surfaceState: GhosttyTerminalSurfaceState,
    appearance: GhosttyTerminalAppearance
) -> (foregroundPacked: UInt32, backgroundPacked: UInt32) {
    let backgroundPacked = surfaceState.cursorColorPacked ?? appearance.cursorColor.packedRGB
    let backgroundColor = GhosttyTerminalColor(packedRGB: backgroundPacked)
    let currentForeground = GhosttyTerminalColor(packedRGB: cell.foregroundPacked)
    let foregroundColor: GhosttyTerminalColor

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

private extension GhosttyTerminalColor {
    init(packedRGB: UInt32) {
        self.init(
            red: UInt8((packedRGB >> 16) & 0xFF),
            green: UInt8((packedRGB >> 8) & 0xFF),
            blue: UInt8(packedRGB & 0xFF)
        )
    }
}

private struct GhosttyTerminalRendererResourceKey: Hashable {
    let deviceIdentifier: ObjectIdentifier
    let fontName: String
    let fontSizeMilliPoints: Int
    let cellWidthMilliPoints: Int
    let cellHeightMilliPoints: Int
    let scaleFactorMilliUnits: Int

    init(
        device: MTLDevice,
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(deviceIdentifier)
        hasher.combine(fontName)
        hasher.combine(fontSizeMilliPoints)
        hasher.combine(cellWidthMilliPoints)
        hasher.combine(cellHeightMilliPoints)
        hasher.combine(scaleFactorMilliUnits)
    }

    static func == (
        lhs: GhosttyTerminalRendererResourceKey,
        rhs: GhosttyTerminalRendererResourceKey
    ) -> Bool {
        lhs.deviceIdentifier == rhs.deviceIdentifier &&
            lhs.fontName == rhs.fontName &&
            lhs.fontSizeMilliPoints == rhs.fontSizeMilliPoints &&
            lhs.cellWidthMilliPoints == rhs.cellWidthMilliPoints &&
            lhs.cellHeightMilliPoints == rhs.cellHeightMilliPoints &&
            lhs.scaleFactorMilliUnits == rhs.scaleFactorMilliUnits
    }
}

@MainActor
final class GhosttyTerminalPipelineCache {
    private static var pipelines: [ObjectIdentifier: TerminalRenderPipeline] = [:]

    static func sharedPipeline(
        device: MTLDevice
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

@MainActor
final class GhosttyTerminalRendererSharedResources {
    let pipeline: TerminalRenderPipeline
    let atlas: TerminalGlyphAtlas

    private static var resources: [GhosttyTerminalRendererResourceKey: GhosttyTerminalRendererSharedResources] = [:]

    private init(
        pipeline: TerminalRenderPipeline,
        atlas: TerminalGlyphAtlas
    ) {
        self.pipeline = pipeline
        self.atlas = atlas
    }

    static func shared(
        device: MTLDevice,
        fontMetrics: GhosttyTerminalFontMetrics,
        scaleFactor: CGFloat
    ) throws -> GhosttyTerminalRendererSharedResources {
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
        let sharedResources = GhosttyTerminalRendererSharedResources(
            pipeline: pipeline,
            atlas: atlas
        )
        resources[key] = sharedResources
        return sharedResources
    }
}

struct RenderContext {
    let view: MTKView
    let drawable: MTLDrawable
    let commandBuffer: MTLCommandBuffer
    let encoder: MTLRenderCommandEncoder
}

struct PreparedFrame {
    let grid: GhosttyTerminalGridMetrics
    let scaleX: CGFloat
    let scaleY: CGFloat
    let cellWidthPx: Float
    let cellHeightPx: Float
}

func linearColor(fromPacked packed: UInt32) -> SIMD4<Float> {
    GhosttyTerminalColor(
        red: UInt8((packed >> 16) & 0xFF),
        green: UInt8((packed >> 8) & 0xFF),
        blue: UInt8(packed & 0xFF)
    )
    .linearRGBA()
}
