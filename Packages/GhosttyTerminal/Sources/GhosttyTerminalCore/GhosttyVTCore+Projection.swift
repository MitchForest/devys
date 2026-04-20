import Foundation
@preconcurrency import CGhosttyVT

private struct GhosttyProjectionMetadata {
    var surfaceState: GhosttyTerminalSurfaceState
    var defaultForegroundPacked: UInt32
    var defaultBackgroundPacked: UInt32
}

private struct GhosttyProjectedFrameRows {
    var dirtyState: GhosttyTerminalDirtyState
    var rows: [GhosttyTerminalProjectedRow]
}

private struct GhosttyProjectedDirtyRows {
    var dirtyRows: [Int]
    var projectedRows: [GhosttyTerminalProjectedRow]
}

extension GhosttyVTCore {
    func surfaceUpdate(
        selectionRange: GhosttyTerminalSelectionRange? = nil
    ) -> GhosttyTerminalSurfaceUpdate {
        _ = updateRenderState()
        guard let renderState else {
            let surfaceState = GhosttyTerminalSurfaceState(cols: 1, rows: 1, selectionRange: selectionRange)
            return GhosttyTerminalSurfaceUpdate(
                surfaceState: surfaceState,
                frameProjection: GhosttyTerminalFrameProjection.empty()
                    .withSelection(selectionRange)
            )
        }

        let metadata = projectionMetadata(
            from: renderState,
            selectionRange: selectionRange
        )
        let frameProjection = frameProjection(
            metadata: metadata,
            renderState: renderState
        )
        return GhosttyTerminalSurfaceUpdate(
            surfaceState: metadata.surfaceState,
            frameProjection: frameProjection
        )
    }

    private func projectionMetadata(
        from renderState: GhosttyRenderState,
        selectionRange: GhosttyTerminalSelectionRange?
    ) -> GhosttyProjectionMetadata {
        let defaults = projectionDefaultColors(from: renderState)
        var surfaceState = queriedSurfaceState(
            from: renderState,
            selectionRange: selectionRange
        )
        if let terminal {
            hydrateProjectionSurfaceState(&surfaceState, terminal: terminal)
        }

        return GhosttyProjectionMetadata(
            surfaceState: surfaceState,
            defaultForegroundPacked: defaults.foregroundPacked,
            defaultBackgroundPacked: defaults.backgroundPacked
        )
    }

    private func queriedSurfaceState(
        from renderState: GhosttyRenderState,
        selectionRange: GhosttyTerminalSelectionRange?
    ) -> GhosttyTerminalSurfaceState {
        var cols: UInt16 = 0
        var rows: UInt16 = 0
        var cursorVisible = false
        var cursorHasValue = false
        var cursorWideTail = false
        var cursorX: UInt16 = 0
        var cursorY: UInt16 = 0
        var cursorStyle = GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK

        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &cols)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &cursorVisible)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &cursorHasValue)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &cursorX)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &cursorY)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL, &cursorWideTail)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &cursorStyle)

        return GhosttyTerminalSurfaceState(
            cols: Int(cols),
            rows: Int(rows),
            cursor: GhosttyTerminalCursor(
                row: cursorHasValue ? Int(cursorY) : 0,
                col: cursorHasValue ? Int(cursorX) : 0
            ),
            cursorVisible: cursorVisible && cursorHasValue,
            cursorStyle: cursorStyle.renderCursorStyle,
            selectionRange: selectionRange,
            cursorWideTail: cursorHasValue && cursorWideTail
        )
    }

    private func projectionDefaultColors(
        from renderState: GhosttyRenderState
    ) -> (foregroundPacked: UInt32, backgroundPacked: UInt32) {
        var defaultForeground = GhosttyColorRgb(appearance.foreground)
        var defaultBackground = GhosttyColorRgb(appearance.background)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLOR_FOREGROUND, &defaultForeground)
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLOR_BACKGROUND, &defaultBackground)
        return (defaultForeground.packed, defaultBackground.packed)
    }

    private func hydrateProjectionSurfaceState(
        _ surfaceState: inout GhosttyTerminalSurfaceState,
        terminal: GhosttyTerminal
    ) {
        var scrollbackRows = 0
        var cursorPendingWrap = false
        var cursorColor = GhosttyColorRgb(appearance.cursorColor)
        var scrollbar = GhosttyTerminalScrollbar(total: 0, offset: 0, len: 0)

        _ = ghostty_terminal_get(
            terminal,
            GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS,
            &scrollbackRows
        )
        _ = ghostty_terminal_get(
            terminal,
            GHOSTTY_TERMINAL_DATA_CURSOR_PENDING_WRAP,
            &cursorPendingWrap
        )
        _ = ghostty_terminal_get(
            terminal,
            GHOSTTY_TERMINAL_DATA_SCROLLBAR,
            &scrollbar
        )
        _ = ghostty_terminal_mode_get(
            terminal,
            ghostty_mode_new(1, false),
            &surfaceState.appCursorMode
        )
        _ = ghostty_terminal_mode_get(
            terminal,
            ghostty_mode_new(2004, false),
            &surfaceState.bracketedPasteMode
        )

        surfaceState.scrollbackRows = max(0, scrollbackRows)
        surfaceState.cursorPendingWrap = cursorPendingWrap
        if ghostty_terminal_get(
            terminal,
            GHOSTTY_TERMINAL_DATA_COLOR_CURSOR,
            &cursorColor
        ) == GHOSTTY_SUCCESS {
            surfaceState.cursorColorPacked = cursorColor.packed
        } else {
            surfaceState.cursorColorPacked = nil
        }
        surfaceState.viewportOffset = max(
            0,
            Int(scrollbar.total) - Int(scrollbar.offset) - Int(scrollbar.len)
        )
    }

    private func frameProjection(
        metadata: GhosttyProjectionMetadata,
        renderState: GhosttyRenderState
    ) -> GhosttyTerminalFrameProjection {
        var dirty = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        _ = ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_DIRTY, &dirty)

        let renderedRows = projectedFrameRows(
            from: renderState,
            cols: metadata.surfaceState.cols,
            rows: metadata.surfaceState.rows,
            dirty: dirty,
            defaultForegroundPacked: metadata.defaultForegroundPacked,
            defaultBackgroundPacked: metadata.defaultBackgroundPacked
        )
        resetGlobalDirtyState(renderState: renderState)

        return GhosttyTerminalFrameProjection(
            cols: metadata.surfaceState.cols,
            rows: metadata.surfaceState.rows,
            defaultForegroundPacked: metadata.defaultForegroundPacked,
            defaultBackgroundPacked: metadata.defaultBackgroundPacked,
            dirtyState: renderedRows.dirtyState,
            rowsByIndex: renderedRows.rows,
            overlay: GhosttyTerminalOverlayProjection(
                selectionRange: metadata.surfaceState.selectionRange,
                cursor: metadata.surfaceState.cursor,
                cursorVisible: metadata.surfaceState.cursorVisible,
                cursorStyle: metadata.surfaceState.cursorStyle,
                viewportOffset: metadata.surfaceState.viewportOffset,
                cursorColorPacked: metadata.surfaceState.cursorColorPacked,
                cursorWideTail: metadata.surfaceState.cursorWideTail,
                cursorPendingWrap: metadata.surfaceState.cursorPendingWrap
            )
        )
    }

    private func projectedFrameRows(
        from renderState: GhosttyRenderState,
        cols: Int,
        rows: Int,
        dirty: GhosttyRenderStateDirty,
        defaultForegroundPacked: UInt32,
        defaultBackgroundPacked: UInt32
    ) -> GhosttyProjectedFrameRows {
        guard let rowIterator = preparedRowIterator(from: renderState) else {
            return cleanProjectedFrameRows(for: dirty)
        }
        guard isDirtyFrame(dirty) else {
            return cleanProjectedFrameRows(for: dirty)
        }

        let projected = collectProjectedDirtyRows(
            from: rowIterator,
            cols: cols,
            rows: rows,
            dirty: dirty,
            defaultForegroundPacked: defaultForegroundPacked,
            defaultBackgroundPacked: defaultBackgroundPacked
        )

        return finalizeProjectedFrameRows(
            dirty: dirty,
            projected: projected
        )
    }

    private func isDirtyFrame(_ dirty: GhosttyRenderStateDirty) -> Bool {
        switch dirty {
        case GHOSTTY_RENDER_STATE_DIRTY_FULL, GHOSTTY_RENDER_STATE_DIRTY_PARTIAL:
            return true
        default:
            return false
        }
    }

    private func cleanProjectedFrameRows(
        for _: GhosttyRenderStateDirty
    ) -> GhosttyProjectedFrameRows {
        GhosttyProjectedFrameRows(
            dirtyState: .clean,
            rows: []
        )
    }

    private func collectProjectedDirtyRows(
        from rowIterator: GhosttyRenderStateRowIterator,
        cols: Int,
        rows: Int,
        dirty: GhosttyRenderStateDirty,
        defaultForegroundPacked: UInt32,
        defaultBackgroundPacked: UInt32
    ) -> GhosttyProjectedDirtyRows {
        var projectedRows: [GhosttyTerminalProjectedRow] = []
        var dirtyRows: [Int] = []
        projectedRows.reserveCapacity(dirty == GHOSTTY_RENDER_STATE_DIRTY_FULL ? rows : 0)
        dirtyRows.reserveCapacity(dirty == GHOSTTY_RENDER_STATE_DIRTY_FULL ? rows : 0)

        var rowIndex = 0
        var clean = false
        while ghostty_render_state_row_iterator_next(rowIterator) {
            let rowIsDirty = currentRowIsDirty(
                in: rowIterator,
                dirty: dirty
            )

            if rowIsDirty {
                dirtyRows.append(rowIndex)
                projectedRows.append(
                    GhosttyTerminalProjectedRow(
                        index: rowIndex,
                        cells: projectedCells(
                            for: rowIterator,
                            cols: cols,
                            defaultForegroundPacked: defaultForegroundPacked,
                            defaultBackgroundPacked: defaultBackgroundPacked
                        ),
                        isDirty: true
                    )
                )
                _ = ghostty_render_state_row_set(
                    rowIterator,
                    GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY,
                    &clean
                )
            }

            rowIndex += 1
        }

        if rowIndex != rows {
            assertionFailure("Ghostty render-state row iterator count did not match viewport rows")
        }

        return GhosttyProjectedDirtyRows(
            dirtyRows: dirtyRows,
            projectedRows: projectedRows
        )
    }

    private func finalizeProjectedFrameRows(
        dirty: GhosttyRenderStateDirty,
        projected: GhosttyProjectedDirtyRows
    ) -> GhosttyProjectedFrameRows {
        switch dirty {
        case GHOSTTY_RENDER_STATE_DIRTY_FULL:
            return GhosttyProjectedFrameRows(
                dirtyState: GhosttyTerminalDirtyState(
                    kind: .full,
                    dirtyRows: projected.dirtyRows
                ),
                rows: projected.projectedRows
            )
        case GHOSTTY_RENDER_STATE_DIRTY_PARTIAL:
            if projected.dirtyRows.isEmpty {
                assertionFailure("Ghostty render state reported partial dirtiness without dirty rows")
                return GhosttyProjectedFrameRows(
                    dirtyState: .clean,
                    rows: []
                )
            }
            return GhosttyProjectedFrameRows(
                dirtyState: GhosttyTerminalDirtyState(
                    kind: .partial,
                    dirtyRows: projected.dirtyRows
                ),
                rows: projected.projectedRows
            )
        default:
            return cleanProjectedFrameRows(for: dirty)
        }
    }

    private func preparedRowIterator(
        from renderState: GhosttyRenderState
    ) -> GhosttyRenderStateRowIterator? {
        guard var rowIterator else { return nil }
        let result = withUnsafeMutablePointer(to: &rowIterator) { pointer in
            ghostty_render_state_get(
                renderState,
                GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
                UnsafeMutableRawPointer(pointer)
            )
        }
        guard result == GHOSTTY_SUCCESS else {
            assertionFailure("Failed to populate Ghostty render-state row iterator")
            return nil
        }
        return rowIterator
    }

    private func currentRowIsDirty(
        in rowIterator: GhosttyRenderStateRowIterator,
        dirty: GhosttyRenderStateDirty
    ) -> Bool {
        switch dirty {
        case GHOSTTY_RENDER_STATE_DIRTY_FULL:
            return true
        case GHOSTTY_RENDER_STATE_DIRTY_PARTIAL:
            var isDirty = false
            _ = ghostty_render_state_row_get(
                rowIterator,
                GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY,
                &isDirty
            )
            return isDirty
        default:
            return false
        }
    }

    private func resetGlobalDirtyState(renderState: GhosttyRenderState) {
        var clean = GHOSTTY_RENDER_STATE_DIRTY_FALSE
        _ = ghostty_render_state_set(
            renderState,
            GHOSTTY_RENDER_STATE_OPTION_DIRTY,
            &clean
        )
    }
}
