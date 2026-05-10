// MetalDiffDocumentView+Rendering.swift

#if os(macOS)
import AppKit
import MetalKit
import Rendering

extension MetalDiffDocumentView {
    func renderUnified(
        snapshot: ResolvedUnifiedDiffDisplaySnapshot,
        visibleOrigin: CGPoint,
        visibleSize: CGSize,
        metrics: RenderMetrics
    ) {
        let contentOriginX = -Float(visibleOrigin.x) * metrics.scale
        let rowHeight = Float(self.metrics.lineHeight) * metrics.scale
        let backgroundWidth = Float(visibleSize.width) * metrics.scale

        for row in snapshot.rows {
            let rowY = (Float(row.rowIndex) * Float(self.metrics.lineHeight) - Float(visibleOrigin.y)) * metrics.scale

            switch row.kind {
            case .hunkHeader:
                underlayBuffer.addQuad(
                    x: 0,
                    y: rowY,
                    width: backgroundWidth,
                    height: rowHeight,
                    color: displayBackgroundColor(for: diffTheme.hunkHeaderBackground)
                )
                if configuration.showsHunkHeaders {
                    renderPacket(
                        row.content.packet,
                        origin: SIMD2(contentOriginX + metrics.gutterPadding, rowY),
                        metrics: metrics,
                        maxX: nil
                    )
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
        snapshot: ResolvedSplitDiffDisplaySnapshot,
        visibleOrigin: CGPoint,
        visibleSize: CGSize,
        metrics: RenderMetrics
    ) {
        let rowHeight = Float(self.metrics.lineHeight) * metrics.scale
        let backgroundWidth = Float(visibleSize.width) * metrics.scale
        let dividerX = backgroundWidth * Float(splitRatio)
        let leftPaneWidth = dividerX
        let rightPaneWidth = backgroundWidth - dividerX - metrics.dividerWidth

        underlayBuffer.addQuad(
            x: dividerX,
            y: 0,
            width: metrics.dividerWidth,
            height: Float(visibleSize.height) * metrics.scale,
            color: displayDividerColor(diffTheme.border)
        )

        for row in snapshot.rows {
            let rowY = (Float(row.rowIndex) * Float(self.metrics.lineHeight) - Float(visibleOrigin.y)) * metrics.scale

            switch row.kind {
            case .hunkHeader:
                underlayBuffer.addQuad(
                    x: 0,
                    y: rowY,
                    width: backgroundWidth,
                    height: rowHeight,
                    color: displayBackgroundColor(for: diffTheme.hunkHeaderBackground)
                )
                if configuration.showsHunkHeaders, let headerPacket = row.headerPacket {
                    renderPacket(
                        headerPacket,
                        origin: SIMD2(metrics.gutterPadding, rowY),
                        metrics: metrics,
                        maxX: nil
                    )
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

    private func renderUnifiedLine(
        row: ResolvedVisibleUnifiedDiffDisplayRow,
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
        renderPacket(
            row.content.packet,
            origin: SIMD2(x + metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: nil
        )
    }

    private func renderUnifiedBackground(
        row: ResolvedVisibleUnifiedDiffDisplayRow,
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
                color: displayBackgroundColor(for: lineBackground)
            )
        }

        if configuration.changeStyle == .fullBackground || configuration.changeStyle == .gutterBars {
            renderChangeBar(
                for: row.lineType,
                x: 0,
                y: rowY,
                metrics: metrics
            )
        }
    }

    private func renderUnifiedLineNumbers(
        row: ResolvedVisibleUnifiedDiffDisplayRow,
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
            color: displayBackgroundColor(for: gutterColor)
        )
        renderLineNumber(row.oldLineNumberPacket, columnX: x, metrics: metrics, rowY: rowY)
        x += metrics.lineNumberColumnWidth

        underlayBuffer.addQuad(
            x: x,
            y: rowY,
            width: metrics.lineNumberColumnWidth,
            height: metrics.lineHeight,
            color: displayBackgroundColor(for: gutterColor)
        )
        renderLineNumber(row.newLineNumberPacket, columnX: x, metrics: metrics, rowY: rowY)
        x += metrics.lineNumberColumnWidth

        return x
    }

    private func renderUnifiedPrefix(
        row: ResolvedVisibleUnifiedDiffDisplayRow,
        metrics: RenderMetrics,
        rowY: Float,
        startX: Float
    ) -> Float {
        guard configuration.showPrefix else { return startX }
        if let prefixPacket = row.prefixPacket {
            renderPacket(
                prefixPacket,
                origin: SIMD2(startX + metrics.gutterPadding, rowY),
                metrics: metrics,
                maxX: nil
            )
        }
        return startX + metrics.prefixColumnWidth
    }

    private func renderSplitLine(
        row: ResolvedVisibleSplitDiffDisplayRow,
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
        } else if configuration.changeStyle != .minimal {
            renderEmptyBuffer(
                x: leftPaneX,
                y: rowY,
                width: leftPaneWidth,
                height: metrics.lineHeight,
                metrics: metrics
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
        } else if configuration.changeStyle != .minimal {
            renderEmptyBuffer(
                x: rightPaneX,
                y: rowY,
                width: rightPaneWidth,
                height: metrics.lineHeight,
                metrics: metrics
            )
        }
    }

    private func renderSplitSide(
        side: ResolvedSplitDiffDisplaySide,
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
                color: displayBackgroundColor(for: lineBackground)
            )
        }

        if changeStyle == .fullBackground || changeStyle == .gutterBars {
            renderChangeBar(
                for: side.lineType,
                x: xOrigin,
                y: rowY,
                metrics: metrics
            )
        }

        var x = xOrigin
        if configuration.showLineNumbers {
            let gutterColor = gutterBackground(for: side.lineType)
            underlayBuffer.addQuad(
                x: x,
                y: rowY,
                width: metrics.lineNumberColumnWidth,
                height: metrics.lineHeight,
                color: displayBackgroundColor(for: gutterColor)
            )
            renderLineNumber(side.lineNumberPacket, columnX: x, metrics: metrics, rowY: rowY)
            x += metrics.lineNumberColumnWidth
        }

        renderPacket(
            side.content.packet,
            origin: SIMD2(x + metrics.gutterPadding, rowY),
            metrics: metrics,
            maxX: xOrigin + backgroundWidth
        )
    }

    private func renderLineNumber(
        _ packet: ResolvedTextRenderPacket?,
        columnX: Float,
        metrics: RenderMetrics,
        rowY: Float
    ) {
        guard let packet else { return }
        let availableWidth = metrics.lineNumberColumnWidth - metrics.gutterPadding
        let textWidth = Float(packet.cellCount) * metrics.cellWidth
        let x = columnX + max(0, availableWidth - textWidth)
        renderPacket(packet, origin: SIMD2(x, rowY), metrics: metrics, maxX: nil)
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
            return diffTheme.addedForeground
        case .removed:
            return diffTheme.removedForeground
        default:
            return SIMD4<Float>(0, 0, 0, 0)
        }
    }

    private func renderChangeBar(
        for type: DiffLine.LineType,
        x: Float,
        y: Float,
        metrics: RenderMetrics
    ) {
        let barColor = lineBarColor(for: type)
        guard barColor.w > 0 else { return }

        let width = Float(configuration.diffDesign.changeBarWidth) * metrics.scale
        switch type {
        case .removed:
            let segment = max(
                1,
                Float(configuration.diffDesign.deletedChangeBarDashHeight) * metrics.scale
            )
            let stride = max(
                segment,
                Float(configuration.diffDesign.deletedChangeBarDashStride) * metrics.scale
            )
            var segmentY: Float = 0
            while segmentY < metrics.lineHeight {
                underlayBuffer.addQuad(
                    x: x,
                    y: y + segmentY,
                    width: width,
                    height: min(segment, metrics.lineHeight - segmentY),
                    color: barColor
                )
                segmentY += stride
            }
        default:
            underlayBuffer.addQuad(
                x: x,
                y: y,
                width: width,
                height: metrics.lineHeight,
                color: barColor
            )
        }
    }

    private func renderEmptyBuffer(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        metrics: RenderMetrics
    ) {
        guard width > 0, height > 0 else { return }
        underlayBuffer.addQuad(
            x: x,
            y: y,
            width: width,
            height: height,
            color: displayBackgroundColor(for: diffTheme.background)
        )
    }
}
#endif
