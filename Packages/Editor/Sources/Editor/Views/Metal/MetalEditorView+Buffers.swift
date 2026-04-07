// MetalEditorView+Buffers.swift
// Buffer building helpers for MetalEditorView.

#if os(macOS)
import AppKit
import MetalKit
import Rendering
import Syntax

extension MetalEditorView {
    // MARK: - Building Buffers

    func buildCellBuffer(rows: [PreparedEditorRow]) {
        guard let lineBuffer = lineBuffer else { return }

        cellBuffer.beginFrame()
        let metrics = makeLineRenderMetrics()

        for row in rows {
            let lineIndex = row.lineIndex
            let lineY = Float(lineBuffer.viewportY(forLine: lineIndex)) * metrics.scale

            if shouldSkipLine(lineY: lineY, cellHeight: metrics.cellHeight) {
                continue
            }

            drawLineNumber(
                row.lineNumberPacket,
                lineY: lineY,
                metrics: metrics
            )

            if let highlighted = row.highlightedLine,
               highlighted.status.isRenderable {
                logHighlightUsageIfNeeded(lineIndex: lineIndex, highlighted: highlighted)
            }
            renderPacket(
                row.contentPacket,
                startX: metrics.gutterWidth,
                lineY: lineY,
                metrics: metrics
            )
        }

        cellBuffer.endFrame()
    }

    struct LineRenderMetrics {
        let scale: Float
        let cellWidth: Float
        let cellHeight: Float
        let gutterWidth: Float
    }

    func makeLineRenderMetrics() -> LineRenderMetrics {
        let scale = Float(scaleFactor)
        return LineRenderMetrics(
            scale: scale,
            cellWidth: Float(metrics.cellWidth) * scale,
            cellHeight: Float(metrics.lineHeight) * scale,
            gutterWidth: Float(metrics.gutterWidth) * scale
        )
    }

    func shouldSkipLine(lineY: Float, cellHeight: Float) -> Bool {
        lineY + cellHeight < 0 || lineY > Float(mtkView.drawableSize.height)
    }

    func drawLineNumber(
        _ packet: ResolvedTextRenderPacket,
        lineY: Float,
        metrics: LineRenderMetrics
    ) {
        let lineNumX = metrics.gutterWidth - Float(packet.cellCount + 1) * metrics.cellWidth
        renderPacket(packet, startX: lineNumX, lineY: lineY, metrics: metrics)
    }

    func renderPacket(
        _ packet: ResolvedTextRenderPacket,
        startX: Float,
        lineY: Float,
        metrics: LineRenderMetrics
    ) {
        var x = startX
        for cell in packet.cells {
            cellBuffer.addCell(
                EditorCellGPU(
                    position: SIMD2(x, lineY),
                    foregroundColor: cell.foregroundColor,
                    backgroundColor: cell.backgroundColor,
                    uvOrigin: cell.uvOrigin,
                    uvSize: cell.uvSize,
                    flags: cell.flags
                )
            )
            x += metrics.cellWidth
        }
    }

    func logHighlightUsageIfNeeded(
        lineIndex: Int,
        highlighted: SyntaxHighlightedLine
    ) {
        #if DEBUG
        if !hasLoggedHighlightUsage {
            hasLoggedHighlightUsage = true
            metalEditorLogger.debug("Render using highlight for line \(lineIndex, privacy: .public)")
            let lineRange = 0..<(self.document?.lineCount ?? 0)
            let cacheCount = self.document?.syntaxController?.currentSnapshot().lines(in: lineRange).count ?? 0
            metalEditorLogger.debug("Cache has \(cacheCount, privacy: .public) entries")
            metalEditorLogger.debug("Line has \(highlighted.tokens.count, privacy: .public) tokens")
            if let first = highlighted.tokens.first {
                let tokenRange = String(describing: first.range)
                metalEditorLogger.debug("First token range: \(tokenRange, privacy: .public)")
                metalEditorLogger.debug("First token fg: \(first.foregroundColor, privacy: .public)")
                let color = hexToLinearColor(first.foregroundColor)
                metalEditorLogger.debug("Converted color: \(String(describing: color), privacy: .public)")
            }
        }
        #endif
    }

    func buildOverlayBuffer() {
        guard let document = document, let lineBuffer = lineBuffer else { return }

        overlayBuffer.clear()

        let scale = Float(scaleFactor)
        let cellWidth = Float(metrics.cellWidth) * scale
        let cellHeight = Float(metrics.lineHeight) * scale
        let gutterWidth = Float(metrics.gutterWidth) * scale

        let cursor = document.cursor
        let cursorY = Float(lineBuffer.viewportY(forLine: cursor.position.line)) * scale
        let cursorX = gutterWidth + Float(cursor.position.column) * cellWidth

        let cursorAlpha: Float
        if hasFocus {
            // Focused: blink the cursor
            let blinkPhase = fmod(uniforms.time * uniforms.cursorBlinkRate, 1.0)
            cursorAlpha = blinkPhase < 0.5 ? cursorColor.w : 0.0
        } else {
            // Unfocused: no cursor
            cursorAlpha = 0.0
        }

        if cursorAlpha > 0 {
            overlayBuffer.addQuad(
                x: cursorX,
                y: cursorY,
                width: 2 * scale,
                height: cellHeight,
                color: SIMD4(cursorColor.x, cursorColor.y, cursorColor.z, cursorAlpha)
            )
        }

        if let selection = document.selection {
            let normalized = selection.normalized

            for line in normalized.start.line...normalized.end.line {
                let lineY = Float(lineBuffer.viewportY(forLine: line)) * scale

                let startCol = line == normalized.start.line ? normalized.start.column : 0
                let endCol = line == normalized.end.line ? normalized.end.column : document.lineLength(at: line)

                let x = gutterWidth + Float(startCol) * cellWidth
                let width = Float(endCol - startCol) * cellWidth

                overlayBuffer.addQuad(
                    x: x,
                    y: lineY,
                    width: width,
                    height: cellHeight,
                    color: selectionColor
                )
            }
        }
    }
}
#endif
