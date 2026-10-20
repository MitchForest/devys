import Foundation
@preconcurrency import CGhosttyVT
import TerminalCore

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

    func mouseWheelData(for event: GhosttyTerminalMouseWheelEvent) -> Data {
        guard let terminal else { return Data() }
        var encoder: GhosttyMouseEncoder?
        guard ghostty_mouse_encoder_new(nil, &encoder) == GHOSTTY_SUCCESS,
              let encoder else {
            return Data()
        }
        defer {
            ghostty_mouse_encoder_free(encoder)
        }

        ghostty_mouse_encoder_setopt_from_terminal(encoder, terminal)
        var size = GhosttyMouseEncoderSize(
            size: MemoryLayout<GhosttyMouseEncoderSize>.stride,
            screen_width: max(1, event.screenWidthPx),
            screen_height: max(1, event.screenHeightPx),
            cell_width: max(1, event.cellWidthPx),
            cell_height: max(1, event.cellHeightPx),
            padding_top: 0,
            padding_bottom: 0,
            padding_right: 0,
            padding_left: 0
        )
        ghostty_mouse_encoder_setopt(
            encoder,
            GHOSTTY_MOUSE_ENCODER_OPT_SIZE,
            &size
        )

        var mouseEvent: GhosttyMouseEvent?
        guard ghostty_mouse_event_new(nil, &mouseEvent) == GHOSTTY_SUCCESS,
              let mouseEvent else {
            return Data()
        }
        defer {
            ghostty_mouse_event_free(mouseEvent)
        }

        ghostty_mouse_event_set_action(mouseEvent, GHOSTTY_MOUSE_ACTION_PRESS)
        ghostty_mouse_event_set_button(
            mouseEvent,
            event.direction == .up ? GHOSTTY_MOUSE_BUTTON_FOUR : GHOSTTY_MOUSE_BUTTON_FIVE
        )
        ghostty_mouse_event_set_position(
            mouseEvent,
            GhosttyMousePosition(x: event.positionX, y: event.positionY)
        )

        var required = 0
        let sizeResult = ghostty_mouse_encoder_encode(
            encoder,
            mouseEvent,
            nil,
            0,
            &required
        )
        guard sizeResult == GHOSTTY_OUT_OF_SPACE || sizeResult == GHOSTTY_SUCCESS else {
            return Data()
        }
        guard required > 0 else { return Data() }

        var output = [CChar](repeating: 0, count: required)
        var written = 0
        let encodeResult = output.withUnsafeMutableBufferPointer { buffer in
            ghostty_mouse_encoder_encode(
                encoder,
                mouseEvent,
                buffer.baseAddress,
                buffer.count,
                &written
            )
        }
        guard encodeResult == GHOSTTY_SUCCESS, written > 0 else {
            return Data()
        }
        return Data(output.prefix(written).map { UInt8(bitPattern: $0) })
    }

    func keyData(
        for event: GhosttyTerminalKeyEvent,
        optionAsAlt: GhosttyTerminalOptionAsAlt
    ) -> Data {
        guard let terminal else { return Data() }
        var encoder: GhosttyKeyEncoder?
        guard ghostty_key_encoder_new(nil, &encoder) == GHOSTTY_SUCCESS,
              let encoder else {
            return Data()
        }
        defer {
            ghostty_key_encoder_free(encoder)
        }

        ghostty_key_encoder_setopt_from_terminal(encoder, terminal)
        var optionAsAltValue = optionAsAlt.ghosttyValue
        ghostty_key_encoder_setopt(
            encoder,
            GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
            &optionAsAltValue
        )

        var keyEvent: GhosttyKeyEvent?
        guard ghostty_key_event_new(nil, &keyEvent) == GHOSTTY_SUCCESS,
              let keyEvent else {
            return Data()
        }
        defer {
            ghostty_key_event_free(keyEvent)
        }

        ghostty_key_event_set_action(keyEvent, event.action.ghosttyKeyAction)
        ghostty_key_event_set_key(keyEvent, event.key.ghosttyValue)
        ghostty_key_event_set_mods(keyEvent, event.modifiers.ghosttyValue)
        ghostty_key_event_set_consumed_mods(keyEvent, 0)
        ghostty_key_event_set_composing(keyEvent, false)
        ghostty_key_event_set_unshifted_codepoint(keyEvent, event.unshiftedCodepoint)

        if let text = event.text, !text.isEmpty {
            let textBuffer = Array(text.utf8CString)
            return textBuffer.withUnsafeBufferPointer { buffer in
                ghostty_key_event_set_utf8(
                    keyEvent,
                    buffer.baseAddress,
                    text.utf8.count
                )
                return encodedKeyData(encoder: encoder, event: keyEvent)
            }
        }

        return encodedKeyData(encoder: encoder, event: keyEvent)
    }

    private func encodedKeyData(encoder: GhosttyKeyEncoder, event: GhosttyKeyEvent) -> Data {
        var required = 0
        let sizeResult = ghostty_key_encoder_encode(
            encoder,
            event,
            nil,
            0,
            &required
        )
        guard sizeResult == GHOSTTY_OUT_OF_SPACE || sizeResult == GHOSTTY_SUCCESS else {
            return Data()
        }
        guard required > 0 else { return Data() }

        var output = [CChar](repeating: 0, count: required)
        var written = 0
        let encodeResult = output.withUnsafeMutableBufferPointer { buffer in
            ghostty_key_encoder_encode(
                encoder,
                event,
                buffer.baseAddress,
                buffer.count,
                &written
            )
        }
        guard encodeResult == GHOSTTY_SUCCESS, written > 0 else {
            return Data()
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

private extension UInt8 {
    var ghosttyKeyAction: GhosttyKeyAction {
        switch self {
        case 0:
            GHOSTTY_KEY_ACTION_RELEASE
        case 2:
            GHOSTTY_KEY_ACTION_REPEAT
        default:
            GHOSTTY_KEY_ACTION_PRESS
        }
    }
}

private extension GhosttyTerminalModifiers {
    var ghosttyValue: GhosttyMods {
        GhosttyMods(rawValue)
    }
}

private extension GhosttyTerminalOptionAsAlt {
    var ghosttyValue: GhosttyOptionAsAlt {
        switch self {
        case .disabled:
            GHOSTTY_OPTION_AS_ALT_FALSE
        case .enabled:
            GHOSTTY_OPTION_AS_ALT_TRUE
        case .leftOnly:
            GHOSTTY_OPTION_AS_ALT_LEFT
        case .rightOnly:
            GHOSTTY_OPTION_AS_ALT_RIGHT
        }
    }
}

private extension GhosttyTerminalKey {
    var ghosttyValue: GhosttyKey {
        switch self {
        case .unidentified: GHOSTTY_KEY_UNIDENTIFIED
        case .backquote: GHOSTTY_KEY_BACKQUOTE
        case .backslash: GHOSTTY_KEY_BACKSLASH
        case .bracketLeft: GHOSTTY_KEY_BRACKET_LEFT
        case .bracketRight: GHOSTTY_KEY_BRACKET_RIGHT
        case .comma: GHOSTTY_KEY_COMMA
        case .digit0: GHOSTTY_KEY_DIGIT_0
        case .digit1: GHOSTTY_KEY_DIGIT_1
        case .digit2: GHOSTTY_KEY_DIGIT_2
        case .digit3: GHOSTTY_KEY_DIGIT_3
        case .digit4: GHOSTTY_KEY_DIGIT_4
        case .digit5: GHOSTTY_KEY_DIGIT_5
        case .digit6: GHOSTTY_KEY_DIGIT_6
        case .digit7: GHOSTTY_KEY_DIGIT_7
        case .digit8: GHOSTTY_KEY_DIGIT_8
        case .digit9: GHOSTTY_KEY_DIGIT_9
        case .equal: GHOSTTY_KEY_EQUAL
        case .intlBackslash: GHOSTTY_KEY_INTL_BACKSLASH
        case .intlRo: GHOSTTY_KEY_INTL_RO
        case .intlYen: GHOSTTY_KEY_INTL_YEN
        case .a: GHOSTTY_KEY_A
        case .b: GHOSTTY_KEY_B
        case .c: GHOSTTY_KEY_C
        case .d: GHOSTTY_KEY_D
        case .e: GHOSTTY_KEY_E
        case .f: GHOSTTY_KEY_F
        case .g: GHOSTTY_KEY_G
        case .h: GHOSTTY_KEY_H
        case .i: GHOSTTY_KEY_I
        case .j: GHOSTTY_KEY_J
        case .k: GHOSTTY_KEY_K
        case .l: GHOSTTY_KEY_L
        case .m: GHOSTTY_KEY_M
        case .n: GHOSTTY_KEY_N
        case .o: GHOSTTY_KEY_O
        case .p: GHOSTTY_KEY_P
        case .q: GHOSTTY_KEY_Q
        case .r: GHOSTTY_KEY_R
        case .s: GHOSTTY_KEY_S
        case .t: GHOSTTY_KEY_T
        case .u: GHOSTTY_KEY_U
        case .v: GHOSTTY_KEY_V
        case .w: GHOSTTY_KEY_W
        case .x: GHOSTTY_KEY_X
        case .y: GHOSTTY_KEY_Y
        case .z: GHOSTTY_KEY_Z
        case .minus: GHOSTTY_KEY_MINUS
        case .period: GHOSTTY_KEY_PERIOD
        case .quote: GHOSTTY_KEY_QUOTE
        case .semicolon: GHOSTTY_KEY_SEMICOLON
        case .slash: GHOSTTY_KEY_SLASH
        case .altLeft: GHOSTTY_KEY_ALT_LEFT
        case .altRight: GHOSTTY_KEY_ALT_RIGHT
        case .backspace: GHOSTTY_KEY_BACKSPACE
        case .capsLock: GHOSTTY_KEY_CAPS_LOCK
        case .contextMenu: GHOSTTY_KEY_CONTEXT_MENU
        case .controlLeft: GHOSTTY_KEY_CONTROL_LEFT
        case .controlRight: GHOSTTY_KEY_CONTROL_RIGHT
        case .enter: GHOSTTY_KEY_ENTER
        case .metaLeft: GHOSTTY_KEY_META_LEFT
        case .metaRight: GHOSTTY_KEY_META_RIGHT
        case .shiftLeft: GHOSTTY_KEY_SHIFT_LEFT
        case .shiftRight: GHOSTTY_KEY_SHIFT_RIGHT
        case .space: GHOSTTY_KEY_SPACE
        case .tab: GHOSTTY_KEY_TAB
        case .delete: GHOSTTY_KEY_DELETE
        case .end: GHOSTTY_KEY_END
        case .home: GHOSTTY_KEY_HOME
        case .insert: GHOSTTY_KEY_INSERT
        case .pageDown: GHOSTTY_KEY_PAGE_DOWN
        case .pageUp: GHOSTTY_KEY_PAGE_UP
        case .arrowDown: GHOSTTY_KEY_ARROW_DOWN
        case .arrowLeft: GHOSTTY_KEY_ARROW_LEFT
        case .arrowRight: GHOSTTY_KEY_ARROW_RIGHT
        case .arrowUp: GHOSTTY_KEY_ARROW_UP
        case .numLock: GHOSTTY_KEY_NUM_LOCK
        case .numpad0: GHOSTTY_KEY_NUMPAD_0
        case .numpad1: GHOSTTY_KEY_NUMPAD_1
        case .numpad2: GHOSTTY_KEY_NUMPAD_2
        case .numpad3: GHOSTTY_KEY_NUMPAD_3
        case .numpad4: GHOSTTY_KEY_NUMPAD_4
        case .numpad5: GHOSTTY_KEY_NUMPAD_5
        case .numpad6: GHOSTTY_KEY_NUMPAD_6
        case .numpad7: GHOSTTY_KEY_NUMPAD_7
        case .numpad8: GHOSTTY_KEY_NUMPAD_8
        case .numpad9: GHOSTTY_KEY_NUMPAD_9
        case .numpadAdd: GHOSTTY_KEY_NUMPAD_ADD
        case .numpadComma: GHOSTTY_KEY_NUMPAD_COMMA
        case .numpadDecimal: GHOSTTY_KEY_NUMPAD_DECIMAL
        case .numpadDivide: GHOSTTY_KEY_NUMPAD_DIVIDE
        case .numpadEnter: GHOSTTY_KEY_NUMPAD_ENTER
        case .numpadEqual: GHOSTTY_KEY_NUMPAD_EQUAL
        case .numpadMultiply: GHOSTTY_KEY_NUMPAD_MULTIPLY
        case .numpadSubtract: GHOSTTY_KEY_NUMPAD_SUBTRACT
        case .escape: GHOSTTY_KEY_ESCAPE
        case .f1: GHOSTTY_KEY_F1
        case .f2: GHOSTTY_KEY_F2
        case .f3: GHOSTTY_KEY_F3
        case .f4: GHOSTTY_KEY_F4
        case .f5: GHOSTTY_KEY_F5
        case .f6: GHOSTTY_KEY_F6
        case .f7: GHOSTTY_KEY_F7
        case .f8: GHOSTTY_KEY_F8
        case .f9: GHOSTTY_KEY_F9
        case .f10: GHOSTTY_KEY_F10
        case .f11: GHOSTTY_KEY_F11
        case .f12: GHOSTTY_KEY_F12
        default: GHOSTTY_KEY_UNIDENTIFIED
        }
    }
}
