import CoreGraphics
import Foundation
import GhosttyTerminalCore
import Metal
import MetalKit
import Rendering
import simd

@MainActor
final class GhosttyMetalTerminalRenderer: NSObject, MTKViewDelegate {
    private enum RowUploadPlan {
        case none
        case full
        case partial([Range<Int>])
    }

    private let pipeline: TerminalRenderPipeline
    private let atlas: TerminalGlyphAtlas
    private let cellBuffer: TerminalCellBuffer
    private let overlayBuffer: TerminalOverlayBuffer
    private let fontMetrics: GhosttyTerminalFontMetrics
    private var rowCellCache: [Int: [TerminalCellGPU]] = [:]
    private var rowRangesByIndex: [Int: Range<Int>] = [:]
    private var flattenedCellsCache: [TerminalCellGPU] = []
    private var lastGridSignature: TerminalGridSignature?
    private let onFirstAtlasMutation: () -> Void
    private let onDrawableUnavailable: () -> Void
    private let onFirstFrameCommit: () -> Void
    private let onFirstInteractiveFrame: () -> Void
    private var hasReportedFirstAtlasMutation = false
    private var hasReportedFirstFrameCommit = false
    private var hasReportedFirstInteractiveFrame = false
    private var lastBlockCursorPresentation: GhosttyBlockCursorPresentation?

    var surfaceState: GhosttyTerminalSurfaceState = .init(cols: 1, rows: 1)
    var frameProjection: GhosttyTerminalFrameProjection = .empty()
    var appearance: GhosttyTerminalAppearance = .defaultDark

    init(
        device: MTLDevice,
        scaleFactor: CGFloat,
        onFirstAtlasMutation: @escaping () -> Void = {},
        onDrawableUnavailable: @escaping () -> Void = {},
        onFirstFrameCommit: @escaping () -> Void = {},
        onFirstInteractiveFrame: @escaping () -> Void = {}
    ) throws {
        let fontMetrics = GhosttyTerminalFontMetrics.default()
        let normalizedScaleFactor = max(scaleFactor, 1)
        let sharedResources = try GhosttyTerminalRendererSharedResources.shared(
            device: device,
            fontMetrics: fontMetrics,
            scaleFactor: normalizedScaleFactor
        )
        self.pipeline = sharedResources.pipeline
        self.atlas = sharedResources.atlas
        self.cellBuffer = TerminalCellBuffer(device: device, initialCapacity: 12_000)
        self.overlayBuffer = TerminalOverlayBuffer(device: device, initialCapacity: 2_000)
        self.fontMetrics = fontMetrics
        self.onFirstAtlasMutation = onFirstAtlasMutation
        self.onDrawableUnavailable = onDrawableUnavailable
        self.onFirstFrameCommit = onFirstFrameCommit
        self.onFirstInteractiveFrame = onFirstInteractiveFrame
        super.init()
    }

    var pointCellSize: CGSize {
        CGSize(width: fontMetrics.cellWidth, height: fontMetrics.cellHeight)
    }

    func draw(in view: MTKView) {
        configureClearColor(for: view)
        guard let renderContext = makeRenderContext(for: view) else {
            onDrawableUnavailable()
            return
        }

        let preparedFrame = prepareFrame(for: renderContext.view)
        let rowUploadPlan = rebuildDirtyRowsIfNeeded(
            grid: preparedFrame.grid,
            cellWidthPx: preparedFrame.cellWidthPx,
            cellHeightPx: preparedFrame.cellHeightPx
        )
        switch rowUploadPlan {
        case .none:
            break
        case .full:
            let packedRows = TerminalCellPacking.packRows(
                rowCellCache,
                totalRows: preparedFrame.grid.rows
            )
            flattenedCellsCache = packedRows.cells
            rowRangesByIndex = packedRows.rowRanges
            cellBuffer.setCells(flattenedCellsCache)
        case .partial(let dirtyRanges):
            cellBuffer.setCells(flattenedCellsCache, dirtyRanges: dirtyRanges)
        }
        populateOverlayBuffer(
            grid: preparedFrame.grid,
            scaleX: preparedFrame.scaleX,
            scaleY: preparedFrame.scaleY
        )
        cellBuffer.syncToGPU()
        overlayBuffer.syncToGPU()

        var uniforms = makeUniforms(
            drawableSize: renderContext.view.drawableSize,
            cellWidthPx: preparedFrame.cellWidthPx,
            cellHeightPx: preparedFrame.cellHeightPx
        )
        drawCells(with: renderContext.encoder, uniforms: &uniforms)
        drawOverlays(with: renderContext.encoder, uniforms: &uniforms)
        commitFrame(renderContext)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

private extension GhosttyMetalTerminalRenderer {
    func configureClearColor(for view: MTKView) {
        let background = appearance.background.linearRGBA()
        view.clearColor = MTLClearColor(
            red: Double(background.x),
            green: Double(background.y),
            blue: Double(background.z),
            alpha: 1
        )
    }

    func makeRenderContext(for view: MTKView) -> RenderContext? {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = pipeline.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return nil
        }

        return RenderContext(
            view: view,
            drawable: drawable,
            commandBuffer: commandBuffer,
            encoder: encoder
        )
    }

    func prepareFrame(for view: MTKView) -> PreparedFrame {
        let scaleX = max(1, view.drawableSize.width / max(view.bounds.width, 1))
        let scaleY = max(1, view.drawableSize.height / max(view.bounds.height, 1))
        let cellWidthPx = Float(pointCellSize.width * scaleX)
        let cellHeightPx = Float(pointCellSize.height * scaleY)
        let grid = GhosttyTerminalGridMetrics(
            cols: max(1, surfaceState.cols),
            rows: max(1, surfaceState.rows),
            cellWidth: pointCellSize.width,
            cellHeight: pointCellSize.height
        )

        return PreparedFrame(
            grid: grid,
            scaleX: scaleX,
            scaleY: scaleY,
            cellWidthPx: cellWidthPx,
            cellHeightPx: cellHeightPx
        )
    }

    func makeUniforms(
        drawableSize: CGSize,
        cellWidthPx _: Float,
        cellHeightPx _: Float
    ) -> TerminalUniforms {
        TerminalUniforms(
            viewportSize: SIMD2(Float(drawableSize.width), Float(drawableSize.height))
        )
    }

    func commitFrame(_ renderContext: RenderContext) {
        renderContext.encoder.endEncoding()
        renderContext.commandBuffer.present(renderContext.drawable)
        renderContext.commandBuffer.commit()
        if hasReportedFirstFrameCommit == false {
            hasReportedFirstFrameCommit = true
            onFirstFrameCommit()
        }
        if hasReportedFirstInteractiveFrame == false, cellBuffer.cellCount > 0 {
            hasReportedFirstInteractiveFrame = true
            onFirstInteractiveFrame()
        }
        cellBuffer.advanceBuffer()
    }

    func drawCells(
        with encoder: MTLRenderCommandEncoder,
        uniforms: inout TerminalUniforms
    ) {
        encoder.setRenderPipelineState(pipeline.cellPipeline)
        encoder.setFragmentTexture(atlas.texture, index: 0)
        encoder.setVertexBuffer(cellBuffer.currentBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<TerminalUniforms>.stride, index: 1)
        guard cellBuffer.cellCount > 0 else { return }
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: cellBuffer.cellCount
        )
    }

    func drawOverlays(
        with encoder: MTLRenderCommandEncoder,
        uniforms: inout TerminalUniforms
    ) {
        guard let overlayMTLBuffer = overlayBuffer.currentBuffer,
              overlayBuffer.vertexCount > 0
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline.overlayPipeline)
        encoder.setVertexBuffer(overlayMTLBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<TerminalUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: overlayBuffer.vertexCount)
    }

    func populateOverlayBuffer(
        grid: GhosttyTerminalGridMetrics,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        overlayBuffer.clear()

        let selectionColor = appearance.selectionBackground.linearRGBA(alpha: 0.55)
        for rect in grid.selectionRects(for: surfaceState.selectionRange) {
            overlayBuffer.addQuad(
                x: Float(rect.minX * scaleX),
                y: Float(rect.minY * scaleY),
                width: Float(rect.width * scaleX),
                height: Float(rect.height * scaleY),
                color: selectionColor
            )
        }

        guard let cursorRect = grid.overlayCursorRect(for: surfaceState) else { return }
        let color = linearColor(fromPacked: surfaceState.cursorColorPacked ?? appearance.cursorColor.packedRGB)
        switch surfaceState.cursorStyle {
        case .block:
            return
        case .underline, .beam:
            overlayBuffer.addQuad(
                x: Float(cursorRect.minX * scaleX),
                y: Float(cursorRect.minY * scaleY),
                width: Float(cursorRect.width * scaleX),
                height: Float(cursorRect.height * scaleY),
                color: color
            )
        case .hollowBlock:
            let line = max(1, floor(min(cursorRect.width, cursorRect.height) * 0.08))
            appendOutline(
                to: overlayBuffer,
                for: cursorRect,
                scaleX: scaleX,
                scaleY: scaleY,
                lineWidth: line,
                color: color
            )
        }
    }

    private func rebuildDirtyRowsIfNeeded(
        grid: GhosttyTerminalGridMetrics,
        cellWidthPx: Float,
        cellHeightPx: Float
    ) -> RowUploadPlan {
        let cursorUpdate = updatedBlockCursorPresentation(
            previous: lastBlockCursorPresentation,
            surfaceState: surfaceState,
            grid: grid
        )
        lastBlockCursorPresentation = cursorUpdate.presentation
        let blockCursorRows = cursorUpdate.dirtyRows
        let requiresFullUpload = resetRowCacheIfNeeded(isFullDirty: frameProjection.dirtyState.kind == .full)
        let rowsByIndex = frameProjectionRowsByIndex(frameProjection)

        switch frameProjection.dirtyState.kind {
        case .clean:
            if requiresFullUpload {
                rebuildRows(
                    visibleProjectedRows(frameProjection, limit: grid.rows),
                    cellWidthPx: cellWidthPx,
                    cellHeightPx: cellHeightPx
                )
                return .full
            }

            let rowsToRebuild = rows(for: blockCursorRows, in: rowsByIndex)
            guard !rowsToRebuild.isEmpty else { return .none }
            return partialUploadPlan(
                rowsToRebuild,
                totalRows: grid.rows,
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
        case .full, .partial:
            if requiresFullUpload {
                rebuildRows(
                    visibleProjectedRows(frameProjection, limit: grid.rows),
                    cellWidthPx: cellWidthPx,
                    cellHeightPx: cellHeightPx
                )
                return .full
            }
            let rowsToRebuild = mergedRows(
                visibleProjectedRows(frameProjection, limit: grid.rows),
                rows(for: blockCursorRows, in: rowsByIndex)
            )
            return partialUploadPlan(
                rowsToRebuild,
                totalRows: grid.rows,
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
        }
    }

    private func resetRowCacheIfNeeded(isFullDirty: Bool) -> Bool {
        let gridSignature = TerminalGridSignature(
            cols: surfaceState.cols,
            rows: surfaceState.rows
        )
        guard TerminalRowCachePolicy.requiresFullReset(
            previous: lastGridSignature,
            current: gridSignature,
            isFullDirty: isFullDirty
        ) else {
            return false
        }

        rowCellCache.removeAll()
        rowRangesByIndex.removeAll()
        flattenedCellsCache.removeAll(keepingCapacity: true)
        lastGridSignature = gridSignature
        return true
    }

    private func rebuildRows(
        _ rows: [GhosttyTerminalProjectedRow],
        cellWidthPx: Float,
        cellHeightPx: Float
    ) {
        guard !rows.isEmpty else {
            frameProjection.dirtyState = .clean
            return
        }

        prepareGlyphAtlas(for: rows)
        for row in rows {
            rowCellCache[row.index] = TerminalCellPacking.gpuCells(
                forRow: row.index,
                cells: cellDescriptors(for: row),
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
        }
        frameProjection.dirtyState = .clean
    }

    private func partialUploadPlan(
        _ rows: [GhosttyTerminalProjectedRow],
        totalRows: Int,
        cellWidthPx: Float,
        cellHeightPx: Float
    ) -> RowUploadPlan {
        guard !rows.isEmpty else {
            frameProjection.dirtyState = .clean
            return .none
        }

        prepareGlyphAtlas(for: rows)
        var dirtyRanges: [Range<Int>] = []
        for row in rows {
            let rowCells = TerminalCellPacking.gpuCells(
                forRow: row.index,
                cells: cellDescriptors(for: row),
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
            rowCellCache[row.index] = rowCells
            dirtyRanges.append(
                replacePackedRow(
                    row.index,
                    with: rowCells,
                    totalRows: totalRows
                )
            )
        }
        frameProjection.dirtyState = .clean
        return dirtyRanges.isEmpty ? .none : .partial(dirtyRanges)
    }

    func replacePackedRow(
        _ rowIndex: Int,
        with rowCells: [TerminalCellGPU],
        totalRows: Int
    ) -> Range<Int> {
        let previousRange = existingPackedRange(for: rowIndex, totalRows: totalRows)
        flattenedCellsCache.replaceSubrange(previousRange, with: rowCells)

        let replacementRange = previousRange.lowerBound..<previousRange.lowerBound + rowCells.count
        rowRangesByIndex[rowIndex] = replacementRange

        let delta = rowCells.count - previousRange.count
        guard delta != 0 else { return replacementRange }

        for laterRowIndex in (rowIndex + 1)..<max(totalRows, 0) {
            guard let laterRange = rowRangesByIndex[laterRowIndex] else { continue }
            rowRangesByIndex[laterRowIndex] =
                (laterRange.lowerBound + delta)..<(laterRange.upperBound + delta)
        }

        return replacementRange
    }

    func existingPackedRange(
        for rowIndex: Int,
        totalRows: Int
    ) -> Range<Int> {
        if let existingRange = rowRangesByIndex[rowIndex] {
            return existingRange
        }

        for nextRowIndex in (rowIndex + 1)..<max(totalRows, 0) {
            if let nextRange = rowRangesByIndex[nextRowIndex] {
                return nextRange.lowerBound..<nextRange.lowerBound
            }
        }

        return flattenedCellsCache.count..<flattenedCellsCache.count
    }

    func prepareGlyphAtlas(
        for rows: [GhosttyTerminalProjectedRow]
    ) {
        guard !rows.isEmpty else { return }

        var requests: [TerminalGlyphRequest] = []
        requests.reserveCapacity(rows.reduce(0) { partialResult, row in
            partialResult + row.cells.count
        })

        for row in rows {
            for cell in row.cells where cell.isRenderable {
                requests.append(
                    TerminalGlyphRequest(
                        grapheme: cell.normalizedGrapheme,
                        cellSpan: cell.isWide ? 2 : 1
                    )
                )
            }
        }

        let mutationCountBefore = atlas.runtimeMutationCount
        atlas.prepareGlyphs(for: requests)
        if hasReportedFirstAtlasMutation == false,
           atlas.runtimeMutationCount > mutationCountBefore {
            hasReportedFirstAtlasMutation = true
            onFirstAtlasMutation()
        }
    }

    func cellDescriptors(
        for row: GhosttyTerminalProjectedRow
    ) -> [TerminalCellDescriptor] {
        var descriptors: [TerminalCellDescriptor] = []
        descriptors.reserveCapacity(row.cells.count)
        let blockCursorCell = resolvedBlockCursorCell(in: row, surfaceState: surfaceState)

        for cell in row.cells where cell.isRenderable {
            let cellSpan = cell.isWide ? 2 : 1
            let entry = atlas.entry(for: cell.normalizedGrapheme, cellSpan: cellSpan)
            let packedColors: (foregroundPacked: UInt32, backgroundPacked: UInt32)
            if blockCursorCell?.column == cell.column {
                packedColors = blockCursorPackedColors(
                    for: cell,
                    surfaceState: surfaceState,
                    appearance: appearance
                )
            } else {
                packedColors = (
                    foregroundPacked: cell.foregroundPacked,
                    backgroundPacked: cell.backgroundPacked
                )
            }
            descriptors.append(
                TerminalCellDescriptor(
                    column: cell.column,
                    cellSpan: cellSpan,
                    foregroundColor: linearColor(fromPacked: packedColors.foregroundPacked),
                    backgroundColor: linearColor(fromPacked: packedColors.backgroundPacked),
                    glyph: entry,
                    flags: cell.isBold ? .bold : []
                )
            )
        }

        return descriptors
    }
}
