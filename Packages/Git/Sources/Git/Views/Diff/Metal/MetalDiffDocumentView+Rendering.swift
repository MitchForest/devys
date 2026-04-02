// MetalDiffDocumentView+Rendering.swift

#if os(macOS)
import AppKit
import MetalKit
import Rendering

extension MetalDiffDocumentView {
    func renderUnified(
        layout: UnifiedDiffLayout,
        startRow: Int,
        endRow: Int,
        visibleOrigin: CGPoint,
        visibleSize: CGSize,
        metrics: RenderMetrics
    ) {
        let contentOriginX = -Float(visibleOrigin.x) * metrics.scale
        let rowHeight = Float(self.metrics.lineHeight) * metrics.scale
        let backgroundWidth = Float(visibleSize.width) * metrics.scale
        let maxRow = min(endRow, layout.rows.count - 1)

        for rowIndex in startRow...maxRow {
            let row = layout.rows[rowIndex]
            let rowY = (Float(rowIndex) * Float(self.metrics.lineHeight) - Float(visibleOrigin.y)) * metrics.scale

            switch row.kind {
            case .hunkHeader:
                let headerColor = diffTheme.hunkHeaderBackground
                underlayBuffer.addQuad(
                    x: 0,
                    y: rowY,
                    width: backgroundWidth,
                    height: rowHeight,
                    color: headerColor
                )
                if configuration.showsHunkHeaders {
                    renderHunkHeaderText(row: row, metrics: metrics, contentOriginX: contentOriginX, rowY: rowY)
                }
            case .line:
                renderUnifiedLine(
                    row: row,
                    metrics: metrics,
                    contentOriginX: contentOriginX,
                    rowY: rowY,
                    backgroundWidth: backgroundWidth
                )
            }
        }
    }

    func renderSplit(
        layout: SplitDiffLayout,
        startRow: Int,
        endRow: Int,
        visibleOrigin: CGPoint,
        visibleSize: CGSize,
        metrics: RenderMetrics
    ) {
        let rowHeight = Float(self.metrics.lineHeight) * metrics.scale
        let backgroundWidth = Float(visibleSize.width) * metrics.scale
        let visibleWidth = backgroundWidth
        let dividerX = visibleWidth * Float(splitRatio)
        let leftPaneWidth = dividerX
        let rightPaneWidth = visibleWidth - dividerX - metrics.dividerWidth
        let maxRow = min(endRow, layout.rows.count - 1)

        let dividerColor = diffTheme.border
        underlayBuffer.addQuad(
            x: dividerX,
            y: 0,
            width: metrics.dividerWidth,
            height: Float(visibleSize.height) * metrics.scale,
            color: dividerColor
        )

        for rowIndex in startRow...maxRow {
            let row = layout.rows[rowIndex]
            let rowY = (Float(rowIndex) * Float(self.metrics.lineHeight) - Float(visibleOrigin.y)) * metrics.scale

            switch row.kind {
            case .hunkHeader:
                let headerColor = diffTheme.hunkHeaderBackground
                underlayBuffer.addQuad(x: 0, y: rowY, width: backgroundWidth, height: rowHeight, color: headerColor)
                if configuration.showsHunkHeaders {
                    renderSplitHeaderText(rowIndex: rowIndex, layout: layout, metrics: metrics, rowY: rowY)
                }
            case .line:
                renderSplitLine(
                    row: row,
                    metrics: metrics,
                    rowY: rowY,
                    dividerX: dividerX,
                    leftPaneWidth: leftPaneWidth,
                    rightPaneWidth: rightPaneWidth
                )
            }
        }
    }

    private func renderHunkHeaderText(
        row: UnifiedDiffRow,
        metrics: RenderMetrics,
        contentOriginX: Float,
        rowY: Float
    ) {
        let context = TextRenderContext(
            text: row.content,
            tokens: nil,
            wordChanges: nil,
            textColor: diffTheme.hunkHeaderForeground,
            backgroundColor: .zero,
            origin: SIMD2(contentOriginX + metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: nil
        )
        renderText(context)
    }

    private func renderSplitHeaderText(
        rowIndex: Int,
        layout: SplitDiffLayout,
        metrics: RenderMetrics,
        rowY: Float
    ) {
        guard let header = layout.hunkHeaders.first(where: { $0.rowIndex == rowIndex }) else { return }
        let text = "@@ -\(header.oldStart),\(header.oldCount) +\(header.newStart),\(header.newCount) @@"

        let context = TextRenderContext(
            text: text,
            tokens: nil,
            wordChanges: nil,
            textColor: diffTheme.hunkHeaderForeground,
            backgroundColor: .zero,
            origin: SIMD2(metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: nil
        )
        renderText(context)
    }

    private func renderUnifiedLine(
        row: UnifiedDiffRow,
        metrics: RenderMetrics,
        contentOriginX: Float,
        rowY: Float,
        backgroundWidth: Float
    ) {
        renderUnifiedBackground(
            row: row,
            metrics: metrics,
            rowY: rowY,
            backgroundWidth: backgroundWidth
        )

        var x = renderUnifiedLineNumbers(
            row: row,
            metrics: metrics,
            rowY: rowY,
            startX: contentOriginX
        )
        x = renderUnifiedPrefix(row: row, metrics: metrics, rowY: rowY, startX: x)
        renderUnifiedContent(row: row, metrics: metrics, rowY: rowY, startX: x)
    }

    private func renderUnifiedBackground(
        row: UnifiedDiffRow,
        metrics: RenderMetrics,
        rowY: Float,
        backgroundWidth: Float
    ) {
        let lineBackground = lineBackgroundColor(for: row.lineType)
        if configuration.changeStyle == .fullBackground {
            underlayBuffer.addQuad(
                x: 0,
                y: rowY,
                width: backgroundWidth,
                height: metrics.lineHeight,
                color: lineBackground
            )
        }

        if configuration.changeStyle == .gutterBars {
            let barColor = lineBarColor(for: row.lineType)
            if barColor.w > 0 {
                underlayBuffer.addQuad(
                    x: 0,
                    y: rowY,
                    width: 3 * metrics.scale,
                    height: metrics.lineHeight,
                    color: barColor
                )
            }
        }
    }

    private func renderUnifiedLineNumbers(
        row: UnifiedDiffRow,
        metrics: RenderMetrics,
        rowY: Float,
        startX: Float
    ) -> Float {
        guard configuration.showLineNumbers else { return startX }
        let gutterColor = gutterBackground(for: row.lineType)
        var x = startX

        underlayBuffer.addQuad(
            x: x,
            y: rowY,
            width: metrics.lineNumberColumnWidth,
            height: metrics.lineHeight,
            color: gutterColor
        )
        renderLineNumber(row.oldLineNumber, columnX: x, metrics: metrics, lineType: row.lineType, rowY: rowY)
        x += metrics.lineNumberColumnWidth

        underlayBuffer.addQuad(
            x: x,
            y: rowY,
            width: metrics.lineNumberColumnWidth,
            height: metrics.lineHeight,
            color: gutterColor
        )
        renderLineNumber(row.newLineNumber, columnX: x, metrics: metrics, lineType: row.lineType, rowY: rowY)
        x += metrics.lineNumberColumnWidth

        return x
    }

    private func renderUnifiedPrefix(
        row: UnifiedDiffRow,
        metrics: RenderMetrics,
        rowY: Float,
        startX: Float
    ) -> Float {
        guard configuration.showPrefix else { return startX }
        let prefix = prefixCharacter(for: row.lineType, isNoNewline: row.lineType == .noNewline)
        let prefixContext = TextRenderContext(
            text: prefix,
            tokens: nil,
            wordChanges: nil,
            textColor: prefixColor(for: row.lineType),
            backgroundColor: .zero,
            origin: SIMD2(startX + metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: nil
        )
        renderText(prefixContext)
        return startX + metrics.prefixColumnWidth
    }

    private func renderUnifiedContent(
        row: UnifiedDiffRow,
        metrics: RenderMetrics,
        rowY: Float,
        startX: Float
    ) {
        let textContext = TextRenderContext(
            text: row.content,
            tokens: tokens(for: row.content),
            wordChanges: row.wordChanges,
            textColor: diffTheme.foreground,
            backgroundColor: .zero,
            origin: SIMD2(startX + metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: nil
        )
        renderText(textContext)
    }

    private func renderSplitLine(
        row: SplitDiffRow,
        metrics: RenderMetrics,
        rowY: Float,
        dividerX: Float,
        leftPaneWidth: Float,
        rightPaneWidth: Float
    ) {
        let leftPaneX: Float = 0
        let rightPaneX = dividerX + metrics.dividerWidth

        if let left = row.left {
            renderSplitSide(
                side: left,
                metrics: metrics,
                xOrigin: leftPaneX,
                rowY: rowY,
                backgroundWidth: leftPaneWidth,
                changeStyle: configuration.changeStyle
            )
        } else if configuration.changeStyle == .fullBackground {
            underlayBuffer.addQuad(
                x: leftPaneX,
                y: rowY,
                width: leftPaneWidth,
                height: metrics.lineHeight,
                color: diffTheme.background
            )
        }

        if let right = row.right {
            renderSplitSide(
                side: right,
                metrics: metrics,
                xOrigin: rightPaneX,
                rowY: rowY,
                backgroundWidth: rightPaneWidth,
                changeStyle: configuration.changeStyle
            )
        } else if configuration.changeStyle == .fullBackground {
            underlayBuffer.addQuad(
                x: rightPaneX,
                y: rowY,
                width: rightPaneWidth,
                height: metrics.lineHeight,
                color: diffTheme.background
            )
        }
    }

    private func renderSplitSide(
        side: SplitDiffSide,
        metrics: RenderMetrics,
        xOrigin: Float,
        rowY: Float,
        backgroundWidth: Float,
        changeStyle: DiffChangeStyle
    ) {
        let lineBackground = lineBackgroundColor(for: side.lineType)
        if changeStyle == .fullBackground {
            underlayBuffer.addQuad(
                x: xOrigin,
                y: rowY,
                width: backgroundWidth,
                height: metrics.lineHeight,
                color: lineBackground
            )
        }

        if changeStyle == .gutterBars {
            let barColor = lineBarColor(for: side.lineType)
            if barColor.w > 0 {
                underlayBuffer.addQuad(
                    x: xOrigin,
                    y: rowY,
                    width: 3 * metrics.scale,
                    height: metrics.lineHeight,
                    color: barColor
                )
            }
        }

        var x = xOrigin
        if configuration.showLineNumbers {
            let gutterColor = gutterBackground(for: side.lineType)
            underlayBuffer.addQuad(
                x: x,
                y: rowY,
                width: metrics.lineNumberColumnWidth,
                height: metrics.lineHeight,
                color: gutterColor
            )
            renderLineNumber(side.lineNumber, columnX: x, metrics: metrics, lineType: side.lineType, rowY: rowY)
            x += metrics.lineNumberColumnWidth
        }

        let textContext = TextRenderContext(
            text: side.content,
            tokens: tokens(for: side.content),
            wordChanges: side.wordChanges,
            textColor: diffTheme.foreground,
            backgroundColor: .zero,
            origin: SIMD2(x + metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: xOrigin + backgroundWidth
        )
        renderText(textContext)
    }

    private func renderLineNumber(
        _ number: Int?,
        columnX: Float,
        metrics: RenderMetrics,
        lineType: DiffLine.LineType,
        rowY: Float
    ) {
        guard let number else { return }
        let numberText = String(number)
        let availableWidth = metrics.lineNumberColumnWidth - metrics.gutterPadding
        let textWidth = Float(numberText.count) * metrics.cellWidth
        let x = columnX + max(0, availableWidth - textWidth)
        let context = TextRenderContext(
            text: numberText,
            tokens: nil,
            wordChanges: nil,
            textColor: diffTheme.lineNumber,
            backgroundColor: gutterBackground(for: lineType),
            origin: SIMD2(x, rowY),
            metrics: metrics,
            maxX: nil
        )
        renderText(context)
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

    private func prefixColor(for type: DiffLine.LineType) -> SIMD4<Float> {
        switch type {
        case .added:
            return hexToLinearColor("#2e7d32")
        case .removed:
            return hexToLinearColor("#c62828")
        default:
            return diffTheme.lineNumber
        }
    }

    private func lineBackgroundColor(for type: DiffLine.LineType) -> SIMD4<Float> {
        switch type {
        case .added:
            return diffTheme.addedLineBackground
        case .removed:
            return diffTheme.removedLineBackground
        case .header:
            return diffTheme.hunkHeaderBackground
        default:
            return .zero
        }
    }

    private func gutterBackground(for type: DiffLine.LineType) -> SIMD4<Float> {
        switch type {
        case .added:
            return diffTheme.addedGutterBackground
        case .removed:
            return diffTheme.removedGutterBackground
        default:
            return diffTheme.gutterBackground
        }
    }

    private func lineBarColor(for type: DiffLine.LineType) -> SIMD4<Float> {
        switch type {
        case .added:
            return diffTheme.addedGutterBackground
        case .removed:
            return diffTheme.removedGutterBackground
        default:
            return SIMD4<Float>(0, 0, 0, 0)
        }
    }

    func wordChangeColor(for type: WordDiff.ChangeType) -> SIMD4<Float> {
        switch type {
        case .added:
            return diffTheme.addedTextBackground
        case .removed:
            return diffTheme.removedTextBackground
        case .unchanged:
            return SIMD4<Float>(0, 0, 0, 0)
        }
    }
}
#endif
