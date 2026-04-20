import Foundation
@preconcurrency import CGhosttyVT

final class GhosttyVTCore {
    let callbackBox = GhosttyVTCallbackBox()
    var appearance: GhosttyTerminalAppearance
    var terminal: GhosttyTerminal?
    var renderState: GhosttyRenderState?
    var rowIterator: GhosttyRenderStateRowIterator?
    var rowCells: GhosttyRenderStateRowCells?

    deinit {
        shutdown()
    }

    init(
        cols: Int,
        rows: Int,
        scrollbackMax: Int,
        appearance: GhosttyTerminalAppearance
    ) throws {
        self.appearance = appearance
        let terminal = try Self.makeTerminal(
            cols: cols,
            rows: rows,
            scrollbackMax: scrollbackMax
        )
        let renderState = try Self.makeRenderState()
        let rowIterator = try Self.makeRowIterator()
        let rowCells = try Self.makeRowCells()

        self.terminal = terminal
        self.renderState = renderState
        self.rowIterator = rowIterator
        self.rowCells = rowCells

        configureCallbacks()
        configureAppearance(appearance)
        resize(
            cols: cols,
            rows: rows,
            cellWidthPx: 8,
            cellHeightPx: 16
        )
        _ = updateRenderState()
    }

    func shutdown() {
        if let rowCells {
            ghostty_render_state_row_cells_free(rowCells)
            self.rowCells = nil
        }
        if let rowIterator {
            ghostty_render_state_row_iterator_free(rowIterator)
            self.rowIterator = nil
        }
        if let renderState {
            ghostty_render_state_free(renderState)
            self.renderState = nil
        }
        if let terminal {
            ghostty_terminal_free(terminal)
            self.terminal = nil
        }
    }

    func write(_ data: Data) -> GhosttyVTWriteResult {
        callbackBox.reset()
        guard let terminal else {
            return GhosttyVTWriteResult(
                surfaceUpdate: GhosttyTerminalSurfaceUpdate(
                    surfaceState: GhosttyTerminalSurfaceState(cols: 1, rows: 1),
                    frameProjection: .empty()
                ),
                outboundWrites: [],
                title: "Terminal",
                workingDirectory: nil,
                bellCountDelta: 0
            )
        }

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            ghostty_terminal_vt_write(terminal, baseAddress, data.count)
        }

        return GhosttyVTWriteResult(
            surfaceUpdate: surfaceUpdate(),
            outboundWrites: callbackBox.pendingWrites,
            title: currentTitle(),
            workingDirectory: currentWorkingDirectory(),
            bellCountDelta: callbackBox.bellCount
        )
    }

    func resize(
        cols: Int,
        rows: Int,
        cellWidthPx: Int,
        cellHeightPx: Int
    ) {
        guard let terminal else { return }
        _ = ghostty_terminal_resize(
            terminal,
            Self.normalizedTerminalDimension(cols),
            Self.normalizedTerminalDimension(rows),
            UInt32(max(1, cellWidthPx)),
            UInt32(max(1, cellHeightPx))
        )
    }

    func scrollViewport(by delta: Int) {
        guard let terminal else { return }
        let behavior = GhosttyTerminalScrollViewport(
            tag: GHOSTTY_SCROLL_VIEWPORT_DELTA,
            value: GhosttyTerminalScrollViewportValue(delta: delta)
        )
        ghostty_terminal_scroll_viewport(terminal, behavior)
    }

    func pasteData(for text: String) -> Data {
        guard let terminal else { return Data(text.utf8) }

        var bracketed = false
        _ = ghostty_terminal_mode_get(
            terminal,
            ghostty_mode_new(2004, false),
            &bracketed
        )

        var input = Array(text.utf8CString.dropLast())
        var required = 0
        let sizeResult = input.withUnsafeMutableBufferPointer { buffer in
            ghostty_paste_encode(
                buffer.baseAddress,
                buffer.count,
                bracketed,
                nil,
                0,
                &required
            )
        }

        guard sizeResult == GHOSTTY_OUT_OF_SPACE || sizeResult == GHOSTTY_SUCCESS else {
            return Data(text.utf8)
        }

        var output = [CChar](repeating: 0, count: max(required, input.count))
        var written = 0
        let encodeResult = input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                ghostty_paste_encode(
                    inputBuffer.baseAddress,
                    inputBuffer.count,
                    bracketed,
                    outputBuffer.baseAddress,
                    outputBuffer.count,
                    &written
                )
            }
        }

        guard encodeResult == GHOSTTY_SUCCESS, written >= 0 else {
            return Data(text.utf8)
        }

        return Data(output.prefix(written).map { UInt8(bitPattern: $0) })
    }

    private static func makeTerminal(
        cols: Int,
        rows: Int,
        scrollbackMax: Int
    ) throws -> GhosttyTerminal {
        var terminal: GhosttyTerminal?
        let options = GhosttyTerminalOptions(
            cols: normalizedTerminalDimension(cols),
            rows: normalizedTerminalDimension(rows),
            max_scrollback: max(0, scrollbackMax)
        )
        guard ghostty_terminal_new(nil, &terminal, options) == GHOSTTY_SUCCESS,
              let terminal else {
            throw GhosttyVTRuntimeError.failedToCreateTerminal
        }
        return terminal
    }

    private static func makeRenderState() throws -> GhosttyRenderState {
        var renderState: GhosttyRenderState?
        guard ghostty_render_state_new(nil, &renderState) == GHOSTTY_SUCCESS,
              let renderState else {
            throw GhosttyVTRuntimeError.failedToCreateRenderState
        }
        return renderState
    }

    private static func makeRowIterator() throws -> GhosttyRenderStateRowIterator {
        var rowIterator: GhosttyRenderStateRowIterator?
        guard ghostty_render_state_row_iterator_new(nil, &rowIterator) == GHOSTTY_SUCCESS,
              let rowIterator else {
            throw GhosttyVTRuntimeError.failedToCreateRenderState
        }
        return rowIterator
    }

    private static func makeRowCells() throws -> GhosttyRenderStateRowCells {
        var rowCells: GhosttyRenderStateRowCells?
        guard ghostty_render_state_row_cells_new(nil, &rowCells) == GHOSTTY_SUCCESS,
              let rowCells else {
            throw GhosttyVTRuntimeError.failedToCreateRenderState
        }
        return rowCells
    }

    private static func normalizedTerminalDimension(_ value: Int) -> UInt16 {
        UInt16(max(1, min(value, Int(UInt16.max))))
    }
}
