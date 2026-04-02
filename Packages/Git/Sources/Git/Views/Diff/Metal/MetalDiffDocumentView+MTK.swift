// MetalDiffDocumentView+MTK.swift

#if os(macOS)
import AppKit
import MetalKit
import Rendering

extension MetalDiffDocumentView {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateUniforms()
    }

    func draw(in view: MTKView) {
        guard let frame = makeFrameContext(view: view) else { return }
        renderLayout(frame)
        encode(frame)
        commandBufferFinalize(frame)
    }
}

private extension MetalDiffDocumentView {
    struct FrameContext {
        let layout: DiffRenderLayout
        let drawable: CAMetalDrawable
        let renderPassDescriptor: MTLRenderPassDescriptor
        let commandBuffer: MTLCommandBuffer
        let visibleOrigin: CGPoint
        let visibleSize: CGSize
        let metrics: RenderMetrics
        let startRow: Int
        let endRow: Int
    }

    func makeFrameContext(view: MTKView) -> FrameContext? {
        guard let layout else { return nil }
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = pipeline.commandQueue.makeCommandBuffer() else {
            return nil
        }

        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        let visibleOrigin = visibleRect.origin
        let visibleSize = visibleRect.size
        let renderMetrics = makeRenderMetrics()
        let totalRows = rowCount(for: layout)
        guard totalRows > 0 else { return nil }

        let rowHeight = CGFloat(metrics.lineHeight)
        let startRow = max(0, Int(floor(visibleOrigin.y / rowHeight)))
        let endRow = min(totalRows - 1, Int(ceil((visibleOrigin.y + visibleSize.height) / rowHeight)))
        guard startRow <= endRow else { return nil }

        return FrameContext(
            layout: layout,
            drawable: drawable,
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            visibleOrigin: visibleOrigin,
            visibleSize: visibleSize,
            metrics: renderMetrics,
            startRow: startRow,
            endRow: endRow
        )
    }

    func renderLayout(_ frame: FrameContext) {
        underlayBuffer.clear()
        cellBuffer.beginFrame()
        overlayBuffer.clear()

        switch frame.layout {
        case .unified(let unified):
            renderUnified(
                layout: unified,
                startRow: frame.startRow,
                endRow: frame.endRow,
                visibleOrigin: frame.visibleOrigin,
                visibleSize: frame.visibleSize,
                metrics: frame.metrics
            )
        case .split(let split):
            renderSplit(
                layout: split,
                startRow: frame.startRow,
                endRow: frame.endRow,
                visibleOrigin: frame.visibleOrigin,
                visibleSize: frame.visibleSize,
                metrics: frame.metrics
            )
        }

        cellBuffer.endFrame()
        underlayBuffer.syncToGPU()
        cellBuffer.syncToGPU()
        overlayBuffer.syncToGPU()
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
