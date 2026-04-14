// MetalEditorView+Buffers.swift
// Buffer building helpers for MetalEditorView.

#if os(macOS)
import AppKit
import MetalKit
import Rendering
import Syntax

extension MetalEditorView {
    private struct OverlayGeometry {
        let scale: Float
        let cellWidth: Float
        let cellHeight: Float
        let gutterWidth: Float
    }

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

        let geometry = overlayGeometry()
        addSearchOverlays(using: geometry, lineBuffer: lineBuffer, document: document)
        addCursorOverlay(using: geometry, lineBuffer: lineBuffer, document: document)
        addSelectionOverlay(using: geometry, lineBuffer: lineBuffer, document: document)
    }

    private func overlayGeometry() -> OverlayGeometry {
        let scale = Float(scaleFactor)
        return OverlayGeometry(
            scale: scale,
            cellWidth: Float(metrics.cellWidth) * scale,
            cellHeight: Float(metrics.lineHeight) * scale,
            gutterWidth: Float(metrics.gutterWidth) * scale
        )
    }

    private func addSearchOverlays(
        using geometry: OverlayGeometry,
        lineBuffer: LineBuffer,
        document: EditorDocument
    ) {
        for match in searchMatches {
            let rangeLowerBound = min(match.startLine, match.endLine)
            let rangeUpperBound = max(match.startLine, match.endLine)
            guard rangeUpperBound >= lineBuffer.visibleRange.lowerBound,
                  rangeLowerBound < lineBuffer.visibleRange.upperBound else {
                continue
            }

            let color = match.id == activeSearchMatchID ? activeSearchMatchColor : searchMatchColor
            addOverlay(
                for: match,
                color: color,
                geometry: geometry,
                lineBuffer: lineBuffer,
                document: document
            )
        }
    }

    private func addCursorOverlay(
        using geometry: OverlayGeometry,
        lineBuffer: LineBuffer,
        document: EditorDocument
    ) {
        let cursor = document.cursor
        let cursorY = Float(lineBuffer.viewportY(forLine: cursor.position.line)) * geometry.scale
        let cursorX = geometry.gutterWidth + Float(cursor.position.column) * geometry.cellWidth

        let cursorAlpha: Float
        if hasFocus {
            let blinkPhase = fmod(uniforms.time * uniforms.cursorBlinkRate, 1.0)
            cursorAlpha = blinkPhase < 0.5 ? cursorColor.w : 0.0
        } else {
            cursorAlpha = 0.0
        }

        guard cursorAlpha > 0 else { return }
        overlayBuffer.addQuad(
            x: cursorX,
            y: cursorY,
            width: 2 * geometry.scale,
            height: geometry.cellHeight,
            color: SIMD4(cursorColor.x, cursorColor.y, cursorColor.z, cursorAlpha)
        )
    }

    private func addSelectionOverlay(
        using geometry: OverlayGeometry,
        lineBuffer: LineBuffer,
        document: EditorDocument
    ) {
        guard let selection = document.selection else { return }
        let normalized = selection.normalized

        for line in normalized.start.line...normalized.end.line {
            let lineY = Float(lineBuffer.viewportY(forLine: line)) * geometry.scale
            let startColumn = line == normalized.start.line ? normalized.start.column : 0
            let endColumn = line == normalized.end.line ? normalized.end.column : document.lineLength(at: line)
            let x = geometry.gutterWidth + Float(startColumn) * geometry.cellWidth
            let width = Float(endColumn - startColumn) * geometry.cellWidth

            overlayBuffer.addQuad(
                x: x,
                y: lineY,
                width: width,
                height: geometry.cellHeight,
                color: selectionColor
            )
        }
    }

    private func addOverlay(
        for match: EditorSearchMatch,
        color: SIMD4<Float>,
        geometry: OverlayGeometry,
        lineBuffer: LineBuffer,
        document: EditorDocument
    ) {
        for line in match.startLine...match.endLine {
            guard line >= 0, line < document.lineCount else { continue }
            let lineY = Float(lineBuffer.viewportY(forLine: line)) * geometry.scale
            let startColumn = line == match.startLine ? match.startColumn : 0
            let endColumn = line == match.endLine ? match.endColumn : document.lineLength(at: line)
            guard endColumn > startColumn else { continue }

            let x = geometry.gutterWidth + Float(startColumn) * geometry.cellWidth
            let width = Float(endColumn - startColumn) * geometry.cellWidth
            overlayBuffer.addQuad(
                x: x,
                y: lineY,
                width: width,
                height: geometry.cellHeight,
                color: color
            )
        }
    }
}
#endif
