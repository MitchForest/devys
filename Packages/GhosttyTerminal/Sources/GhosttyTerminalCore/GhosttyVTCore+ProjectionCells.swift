import Foundation
@preconcurrency import CGhosttyVT

extension GhosttyVTCore {
    func projectedCells(
        for iterator: GhosttyRenderStateRowIterator,
        cols: Int,
        defaultForegroundPacked: UInt32,
        defaultBackgroundPacked: UInt32
    ) -> [GhosttyTerminalProjectedCell] {
        guard let rowCells = preparedRowCells(for: iterator) else { return [] }

        var cells: [GhosttyTerminalProjectedCell] = []
        cells.reserveCapacity(cols)

        while cells.count < cols, ghostty_render_state_row_cells_next(rowCells) {
            cells.append(
                projectedCell(
                    from: rowCells,
                    column: cells.count,
                    defaultForegroundPacked: defaultForegroundPacked,
                    defaultBackgroundPacked: defaultBackgroundPacked
                )
            )
        }

        while cells.count < cols {
            cells.append(
                blankProjectedCell(
                    column: cells.count,
                    defaultForegroundPacked: defaultForegroundPacked,
                    defaultBackgroundPacked: defaultBackgroundPacked
                )
            )
        }

        return cells
    }

    private func preparedRowCells(
        for iterator: GhosttyRenderStateRowIterator
    ) -> GhosttyRenderStateRowCells? {
        guard var rowCells else { return nil }
        let result = withUnsafeMutablePointer(to: &rowCells) { pointer in
            ghostty_render_state_row_get(
                iterator,
                GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
                UnsafeMutableRawPointer(pointer)
            )
        }
        guard result == GHOSTTY_SUCCESS else {
            assertionFailure("Failed to populate Ghostty render-state row cells")
            return nil
        }
        return rowCells
    }

    private func projectedCell(
        from rowCells: GhosttyRenderStateRowCells,
        column: Int,
        defaultForegroundPacked: UInt32,
        defaultBackgroundPacked: UInt32
    ) -> GhosttyTerminalProjectedCell {
        let text = renderCellText(from: rowCells)
        let foreground = renderCellColor(
            from: rowCells,
            key: GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR,
            fallback: GhosttyColorRgb(packed: defaultForegroundPacked)
        )
        let background = renderCellColor(
            from: rowCells,
            key: GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR,
            fallback: GhosttyColorRgb(packed: defaultBackgroundPacked)
        )
        let style = renderCellStyle(from: rowCells)
        let wideState = renderCellWideState(from: rowCells)
        let isContinuation = wideState == GHOSTTY_CELL_WIDE_SPACER_TAIL ||
            wideState == GHOSTTY_CELL_WIDE_SPACER_HEAD
        let effectiveForeground: GhosttyColorRgb
        let effectiveBackground: GhosttyColorRgb

        if style.inverse {
            effectiveForeground = background
            effectiveBackground = foreground
        } else {
            effectiveForeground = foreground
            effectiveBackground = background
        }

        return GhosttyTerminalProjectedCell(
            column: column,
            grapheme: isContinuation ? "" : text,
            foregroundPacked: effectiveForeground.packed,
            backgroundPacked: effectiveBackground.packed,
            isBold: style.bold,
            isWide: wideState == GHOSTTY_CELL_WIDE_WIDE,
            isWideContinuation: isContinuation
        )
    }

    func blankProjectedCell(
        column: Int,
        defaultForegroundPacked: UInt32,
        defaultBackgroundPacked: UInt32
    ) -> GhosttyTerminalProjectedCell {
        GhosttyTerminalProjectedCell(
            column: column,
            grapheme: " ",
            foregroundPacked: defaultForegroundPacked,
            backgroundPacked: defaultBackgroundPacked
        )
    }

    private func renderCellWideState(
        from rowCells: GhosttyRenderStateRowCells
    ) -> GhosttyCellWide {
        var rawCell: GhosttyCell = 0
        _ = ghostty_render_state_row_cells_get(
            rowCells,
            GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW,
            &rawCell
        )

        var wide = GHOSTTY_CELL_WIDE_NARROW
        _ = ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_WIDE, &wide)
        return wide
    }

    private func renderCellText(
        from rowCells: GhosttyRenderStateRowCells
    ) -> String {
        var graphemeCount: UInt32 = 0
        _ = ghostty_render_state_row_cells_get(
            rowCells,
            GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
            &graphemeCount
        )
        guard graphemeCount > 0 else { return " " }

        var buffer = Array(repeating: UInt32(0), count: Int(graphemeCount))
        _ = buffer.withUnsafeMutableBufferPointer { pointer in
            ghostty_render_state_row_cells_get(
                rowCells,
                GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
                pointer.baseAddress
            )
        }

        return String(String.UnicodeScalarView(buffer.compactMap(UnicodeScalar.init)))
    }

    private func renderCellColor(
        from rowCells: GhosttyRenderStateRowCells,
        key: GhosttyRenderStateRowCellsData,
        fallback: GhosttyColorRgb
    ) -> GhosttyColorRgb {
        var color = fallback
        _ = ghostty_render_state_row_cells_get(rowCells, key, &color)
        return color
    }

    private func renderCellStyle(
        from rowCells: GhosttyRenderStateRowCells
    ) -> GhosttyStyle {
        var style = emptyStyle()
        ghostty_style_default(&style)
        _ = ghostty_render_state_row_cells_get(
            rowCells,
            GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
            &style
        )
        return style
    }
}
