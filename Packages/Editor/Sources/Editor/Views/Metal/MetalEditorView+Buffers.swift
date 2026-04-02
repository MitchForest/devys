// MetalEditorView+Buffers.swift
// Buffer building helpers for MetalEditorView.

#if os(macOS)
import AppKit
import MetalKit
import Rendering

extension MetalEditorView {
    // MARK: - Building Buffers

    func buildCellBuffer(lines: [String], startLine: Int) {
        guard let lineBuffer = lineBuffer else { return }

        cellBuffer.beginFrame()
        let metrics = makeLineRenderMetrics()

        for (offset, text) in lines.enumerated() {
            let lineIndex = startLine + offset
            let lineY = Float(lineBuffer.viewportY(forLine: lineIndex)) * metrics.scale

            if shouldSkipLine(lineY: lineY, cellHeight: metrics.cellHeight) {
                continue
            }

            drawLineNumber(
                lineIndex: lineIndex,
                lineY: lineY,
                metrics: metrics
            )

            if let highlighted = cachedHighlightedLines[lineIndex] {
                logHighlightUsageIfNeeded(lineIndex: lineIndex, highlighted: highlighted)
                renderHighlightedLine(
                    highlighted,
                    text: text,
                    lineY: lineY,
                    metrics: metrics
                )
            } else {
                renderPlainLine(text, lineY: lineY, metrics: metrics)
            }
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
        lineIndex: Int,
        lineY: Float,
        metrics: LineRenderMetrics
    ) {
        let lineNumStr = String(lineIndex + 1)
        let lineNumX = metrics.gutterWidth - Float(lineNumStr.count + 1) * metrics.cellWidth
        for (i, char) in lineNumStr.enumerated() {
            let entry = glyphAtlas.entry(for: char)
            cellBuffer.addCell(
                EditorCellGPU(
                    position: SIMD2(lineNumX + Float(i) * metrics.cellWidth, lineY),
                    foregroundColor: lineNumberColor,
                    backgroundColor: backgroundColor,
                    uvOrigin: entry.uvOrigin,
                    uvSize: entry.uvSize,
                    flags: EditorCellFlags.lineNumber.rawValue
                )
            )
        }
    }

    func renderHighlightedLine(
        _ highlighted: HighlightedLine,
        text: String,
        lineY: Float,
        metrics: LineRenderMetrics
    ) {
        var x = metrics.gutterWidth
        var renderedUpTo = 0  // Track how many characters we've rendered
        
        for token in highlighted.tokens {
            let fgColor = hexToLinearColor(token.foregroundColor)
            let bgColor = token.backgroundColor.map { hexToLinearColor($0) } ?? backgroundColor

            let tokenText = textForToken(token, in: text)
            for char in tokenText {
                let entry = glyphAtlas.entry(for: char)
                let flags = tokenFlags(token)

                cellBuffer.addCell(
                    EditorCellGPU(
                        position: SIMD2(x, lineY),
                        foregroundColor: fgColor,
                        backgroundColor: bgColor,
                        uvOrigin: entry.uvOrigin,
                        uvSize: entry.uvSize,
                        flags: flags
                    )
                )
                x += metrics.cellWidth
                renderedUpTo += 1
            }
        }
        
        // If text has changed and has more characters than the cached tokens cover,
        // render the remaining characters in plain foreground color.
        // This handles the case where the user types new characters and the
        // highlight cache is stale.
        if renderedUpTo < text.count {
            let remainingText = text.dropFirst(renderedUpTo)
            for char in remainingText {
                let entry = glyphAtlas.entry(for: char)
                cellBuffer.addCell(
                    EditorCellGPU(
                        position: SIMD2(x, lineY),
                        foregroundColor: foregroundColor,
                        backgroundColor: backgroundColor,
                        uvOrigin: entry.uvOrigin,
                        uvSize: entry.uvSize,
                        flags: 0
                    )
                )
                x += metrics.cellWidth
            }
        }
    }

    func renderPlainLine(_ text: String, lineY: Float, metrics: LineRenderMetrics) {
        var x = metrics.gutterWidth
        for char in text {
            let entry = glyphAtlas.entry(for: char)
            cellBuffer.addCell(
                EditorCellGPU(
                    position: SIMD2(x, lineY),
                    foregroundColor: foregroundColor,
                    backgroundColor: backgroundColor,
                    uvOrigin: entry.uvOrigin,
                    uvSize: entry.uvSize,
                    flags: 0
                )
            )
            x += metrics.cellWidth
        }
    }

    func textForToken(_ token: HighlightedToken, in text: String) -> String {
        let tokenStart = token.range.lowerBound
        let tokenEnd = min(token.range.upperBound, text.utf16.count)
        let startIdx = text.utf16Index(at: tokenStart)
        let endIdx = text.utf16Index(at: tokenEnd)
        return String(text[startIdx..<endIdx])
    }

    func tokenFlags(_ token: HighlightedToken) -> UInt32 {
        var flags: UInt32 = 0
        if token.fontStyle.contains(.bold) { flags |= EditorCellFlags.bold.rawValue }
        if token.fontStyle.contains(.italic) { flags |= EditorCellFlags.italic.rawValue }
        return flags
    }

    func logHighlightUsageIfNeeded(
        lineIndex: Int,
        highlighted: HighlightedLine
    ) {
        #if DEBUG
        if !hasLoggedHighlightUsage {
            hasLoggedHighlightUsage = true
            metalEditorLogger.debug("Render using highlight for line \(lineIndex, privacy: .public)")
            metalEditorLogger.debug("Cache has \(self.cachedHighlightedLines.count, privacy: .public) entries")
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

        let blinkPhase = fmod(uniforms.time * uniforms.cursorBlinkRate, 1.0)
        let cursorAlpha: Float = blinkPhase < 0.5 ? cursorColor.w : 0.0

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
