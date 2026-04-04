// MetalDiffDocumentView+MTK.swift

#if os(macOS)
import AppKit
import MetalKit
import Rendering
import Syntax

extension MetalDiffDocumentView {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateUniforms()
        refreshPreparedFrame()
    }

    func draw(in view: MTKView) {
        SyntaxRuntimeDiagnostics.beginRenderPass(surface: "diff")
        defer { SyntaxRuntimeDiagnostics.endRenderPass(surface: "diff") }
        guard let frame = makeFrameContext(view: view) else { return }
        recordVisibleDiagnostics(frame.preparedFrame.displaySnapshot)
        renderLayout(frame)
        encode(frame)
        commandBufferFinalize(frame)
    }
}

extension MetalDiffDocumentView {
    struct FrameContext {
        let preparedFrame: PreparedFrame
        let drawable: CAMetalDrawable
        let renderPassDescriptor: MTLRenderPassDescriptor
        let commandBuffer: MTLCommandBuffer
    }

    func makeFrameContext(view: MTKView) -> FrameContext? {
        guard let preparedFrame else { return nil }
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = pipeline.commandQueue.makeCommandBuffer() else {
            return nil
        }

        return FrameContext(
            preparedFrame: preparedFrame,
            drawable: drawable,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }

    func renderLayout(_ frame: FrameContext) {
        underlayBuffer.clear()
        cellBuffer.beginFrame()
        overlayBuffer.clear()

        switch frame.preparedFrame.resolvedSnapshot {
        case .unified(let unified):
            renderUnified(
                snapshot: unified,
                visibleOrigin: frame.preparedFrame.visibleOrigin,
                visibleSize: frame.preparedFrame.visibleSize,
                metrics: frame.preparedFrame.renderMetrics
            )
        case .split(let split):
            renderSplit(
                snapshot: split,
                visibleOrigin: frame.preparedFrame.visibleOrigin,
                visibleSize: frame.preparedFrame.visibleSize,
                metrics: frame.preparedFrame.renderMetrics
            )
        }

        cellBuffer.endFrame()
        underlayBuffer.syncToGPU()
        cellBuffer.syncToGPU()
        overlayBuffer.syncToGPU()
    }

    func recordVisibleDiagnostics(_ snapshot: DiffDisplaySnapshot) {
        let highlightedCount = snapshot.actualHighlightedLineCount
        let staleCount = snapshot.staleHighlightedLineCount
        let loadingCount = snapshot.loadingLineCount
        let prefetchHits = highlightedCount + staleCount
        let prefetchMisses = loadingCount
        recordVisiblePresentationDiagnostics(
            highlightedCount: highlightedCount,
            staleCount: staleCount,
            loadingCount: loadingCount,
            prefetchHits: prefetchHits,
            prefetchMisses: prefetchMisses
        )
        recordOpenAndRevisitDiagnostics(for: snapshot)
        completePendingVisibleRefreshIfNeeded(for: snapshot)
        recordScrollDiagnosticsIfNeeded(
            highlightedCount: highlightedCount,
            staleCount: staleCount,
            loadingCount: loadingCount,
            prefetchHits: prefetchHits,
            prefetchMisses: prefetchMisses
        )
    }

    private func recordVisiblePresentationDiagnostics(
        highlightedCount: Int,
        staleCount: Int,
        loadingCount: Int,
        prefetchHits: Int,
        prefetchMisses: Int
    ) {
        SyntaxRuntimeDiagnostics.recordVisiblePresentation(
            surface: "diff",
            actualHighlightedLines: highlightedCount,
            staleLines: staleCount,
            loadingLines: loadingCount
        )
        SyntaxRuntimeDiagnostics.recordPrefetchSample(
            surface: "diff",
            hits: prefetchHits,
            misses: prefetchMisses
        )
    }

    private func recordOpenAndRevisitDiagnostics(for snapshot: DiffDisplaySnapshot) {
        recordOpenDiagnosticsIfNeeded(allVisibleSyntaxLinesActual: snapshot.allVisibleSyntaxLinesActual)
        recordRevisitDiagnosticsIfNeeded(allVisibleSyntaxLinesActual: snapshot.allVisibleSyntaxLinesActual)
    }

    private func recordOpenDiagnosticsIfNeeded(allVisibleSyntaxLinesActual: Bool) {
        if let openTrackingIdentifier, !hasRecordedOpenInteractiveFrame {
            SyntaxRuntimeDiagnostics.markFirstInteractiveFrame(
                surface: "diff",
                identifier: openTrackingIdentifier
            )
            hasRecordedOpenInteractiveFrame = true
        }

        if let openTrackingIdentifier,
           !hasRecordedOpenHighlightedFrame,
           allVisibleSyntaxLinesActual {
            SyntaxRuntimeDiagnostics.markFirstHighlightedFrame(
                surface: "diff",
                identifier: openTrackingIdentifier
            )
            hasRecordedOpenHighlightedFrame = true
        }
    }

    private func recordRevisitDiagnosticsIfNeeded(allVisibleSyntaxLinesActual: Bool) {
        if let revisitTrackingIdentifier, !hasRecordedRevisitInteractiveFrame {
            SyntaxRuntimeDiagnostics.markFirstInteractiveRevisitFrame(
                surface: "diff",
                identifier: revisitTrackingIdentifier
            )
            hasRecordedRevisitInteractiveFrame = true
        }

        if let revisitTrackingIdentifier,
           !hasRecordedRevisitHighlightedFrame,
           allVisibleSyntaxLinesActual {
            SyntaxRuntimeDiagnostics.markFirstHighlightedRevisitFrame(
                surface: "diff",
                identifier: revisitTrackingIdentifier
            )
            hasRecordedRevisitHighlightedFrame = true
        }
    }

    private func completePendingVisibleRefreshIfNeeded(for snapshot: DiffDisplaySnapshot) {
        guard let pendingVisibleRefreshIdentifier, snapshot.allVisibleSyntaxLinesActual else { return }
        SyntaxRuntimeDiagnostics.completeVisibleEdit(
            surface: "diff",
            identifier: pendingVisibleRefreshIdentifier
        )
        self.pendingVisibleRefreshIdentifier = nil
    }

    private func recordScrollDiagnosticsIfNeeded(
        highlightedCount: Int,
        staleCount: Int,
        loadingCount: Int,
        prefetchHits: Int,
        prefetchMisses: Int
    ) {
        guard shouldRecordScrollTrace else { return }
        SyntaxRuntimeDiagnostics.recordScrollTrace(
            surface: "diff",
            deltaY: Double(lastScrollDeltaY),
            actualHighlightedLines: highlightedCount,
            staleLines: staleCount,
            loadingLines: loadingCount,
            prefetchHits: prefetchHits,
            prefetchMisses: prefetchMisses
        )
        shouldRecordScrollTrace = false
    }

    func encode(_ frame: FrameContext) {
        guard let encoder = frame.commandBuffer.makeRenderCommandEncoder(
            descriptor: frame.renderPassDescriptor
        ) else {
            return
        }

        encodeOverlay(buffer: underlayBuffer, encoder: encoder)
        drawCells(encoder: encoder)
        encodeOverlay(buffer: overlayBuffer, encoder: encoder)

        encoder.endEncoding()
    }

    func encodeOverlay(buffer: EditorOverlayBuffer, encoder: MTLRenderCommandEncoder) {
        guard buffer.vertexCount > 0, let metalBuffer = buffer.currentBuffer else { return }
        encoder.setRenderPipelineState(pipeline.overlayPipeline)
        encoder.setVertexBuffer(metalBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: buffer.vertexCount)
    }

    func commandBufferFinalize(_ frame: FrameContext) {
        frame.commandBuffer.present(frame.drawable)
        frame.commandBuffer.commit()
        cellBuffer.advanceBuffer()
    }

    func makeRenderMetrics() -> RenderMetrics {
        let scale = Float(scaleFactor)
        let cellWidth = Float(metrics.cellWidth) * scale
        let lineHeight = Float(metrics.lineHeight) * scale
        let gutterPadding = Float(4) * scale
        let lineNumberColumnWidth = configuration.showLineNumbers
            ? Float(CGFloat(max(1, layout?.maxLineNumberDigits ?? 1)) * metrics.cellWidth + 8) * scale
            : 0
        let prefixColumnWidth = configuration.showPrefix ? cellWidth * 2 : 0
        let dividerWidth: Float = 1 * scale

        return RenderMetrics(
            scale: scale,
            cellWidth: cellWidth,
            lineHeight: lineHeight,
            lineNumberColumnWidth: lineNumberColumnWidth,
            prefixColumnWidth: prefixColumnWidth,
            gutterPadding: gutterPadding,
            dividerWidth: dividerWidth
        )
    }

    func rowCount(for layout: DiffRenderLayout) -> Int {
        switch layout {
        case .unified(let unified):
            return unified.rows.count
        case .split(let split):
            return split.rows.count
        }
    }

    func drawCells(encoder: MTLRenderCommandEncoder) {
        guard cellBuffer.cellCount > 0 else { return }
        encoder.setRenderPipelineState(pipeline.cellPipeline)
        encoder.setVertexBuffer(cellBuffer.currentBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
        if let texture = glyphAtlas.texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: cellBuffer.cellCount
        )
    }
}
#endif
