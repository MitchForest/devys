import Foundation
@preconcurrency import CGhosttyVT

extension GhosttyVTCore {
    func updateRenderState() -> Bool {
        guard let renderState, let terminal else { return false }
        return ghostty_render_state_update(renderState, terminal) == GHOSTTY_SUCCESS
    }

    func configureCallbacks() {
        guard let terminal else { return }

        let userdata = Unmanaged.passUnretained(callbackBox).toOpaque()
        let writePtyPointer = unsafeBitCast(
            ghosttyVTWritePtyCallback as GhosttyTerminalWritePtyFn,
            to: UnsafeRawPointer.self
        )
        let bellPointer = unsafeBitCast(
            ghosttyVTBellCallback as GhosttyTerminalBellFn,
            to: UnsafeRawPointer.self
        )
        let titleChangedPointer = unsafeBitCast(
            ghosttyVTTitleChangedCallback as GhosttyTerminalTitleChangedFn,
            to: UnsafeRawPointer.self
        )
        let colorSchemePointer = unsafeBitCast(
            ghosttyVTColorSchemeCallback as GhosttyTerminalColorSchemeFn,
            to: UnsafeRawPointer.self
        )

        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_USERDATA, userdata)
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_WRITE_PTY, writePtyPointer)
        _ = ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_BELL, bellPointer)
        _ = ghostty_terminal_set(
            terminal,
            GHOSTTY_TERMINAL_OPT_TITLE_CHANGED,
            titleChangedPointer
        )
        _ = ghostty_terminal_set(
            terminal,
            GHOSTTY_TERMINAL_OPT_COLOR_SCHEME,
            colorSchemePointer
        )
    }

    func configureAppearance(_ appearance: GhosttyTerminalAppearance) {
        guard let terminal else { return }
        self.appearance = appearance
        callbackBox.colorScheme = appearance.colorScheme.ghosttyColorScheme

        var foreground = GhosttyColorRgb(appearance.foreground)
        var background = GhosttyColorRgb(appearance.background)
        var cursor = GhosttyColorRgb(appearance.cursorColor)

        _ = ghostty_terminal_set(
            terminal,
            GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND,
            &foreground
        )
        _ = ghostty_terminal_set(
            terminal,
            GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND,
            &background
        )
        _ = ghostty_terminal_set(
            terminal,
            GHOSTTY_TERMINAL_OPT_COLOR_CURSOR,
            &cursor
        )

        guard var palette = defaultPalette(for: terminal) else { return }
        for (index, color) in appearance.palette.enumerated() {
            palette[index] = GhosttyColorRgb(color)
        }
        _ = palette.withUnsafeMutableBufferPointer { buffer in
            ghostty_terminal_set(
                terminal,
                GHOSTTY_TERMINAL_OPT_COLOR_PALETTE,
                buffer.baseAddress
            )
        }
    }

    func currentTitle() -> String {
        stringValue(
            for: GHOSTTY_TERMINAL_DATA_TITLE,
            fallback: "Terminal"
        ) ?? "Terminal"
    }

    func currentWorkingDirectory() -> String? {
        stringValue(for: GHOSTTY_TERMINAL_DATA_PWD)
    }

    private func stringValue(
        for key: GhosttyTerminalData,
        fallback: String? = nil
    ) -> String? {
        guard let terminal else { return fallback }
        var value = GhosttyString(ptr: nil, len: 0)

        guard ghostty_terminal_get(terminal, key, &value) == GHOSTTY_SUCCESS,
              let pointer = value.ptr,
              value.len > 0 else {
            return fallback
        }

        let data = Data(bytes: pointer, count: value.len)
        return String(data: data, encoding: .utf8) ?? fallback
    }

    private func defaultPalette(
        for terminal: GhosttyTerminal
    ) -> [GhosttyColorRgb]? {
        var palette = Array(
            repeating: GhosttyColorRgb(r: 0, g: 0, b: 0),
            count: 256
        )
        let result = palette.withUnsafeMutableBufferPointer { buffer in
            ghostty_terminal_get(
                terminal,
                GHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT,
                buffer.baseAddress
            )
        }
        guard result == GHOSTTY_SUCCESS else {
            assertionFailure("Failed to read Ghostty default palette")
            return nil
        }
        return palette
    }
}

final class GhosttyVTCallbackBox {
    var pendingWrites: [Data] = []
    var bellCount = 0
    var colorScheme = GHOSTTY_COLOR_SCHEME_DARK

    func reset() {
        pendingWrites.removeAll(keepingCapacity: true)
        bellCount = 0
    }
}

let ghosttyVTWritePtyCallback: @convention(c) (
    GhosttyTerminal?,
    UnsafeMutableRawPointer?,
    UnsafePointer<UInt8>?,
    Int
) -> Void = { _, userdata, bytes, length in
    guard let userdata,
          let bytes,
          length > 0 else {
        return
    }

    let box = Unmanaged<GhosttyVTCallbackBox>.fromOpaque(userdata).takeUnretainedValue()
    box.pendingWrites.append(Data(bytes: bytes, count: length))
}

let ghosttyVTBellCallback: @convention(c) (
    GhosttyTerminal?,
    UnsafeMutableRawPointer?
) -> Void = { _, userdata in
    guard let userdata else { return }
    let box = Unmanaged<GhosttyVTCallbackBox>.fromOpaque(userdata).takeUnretainedValue()
    box.bellCount += 1
}

let ghosttyVTTitleChangedCallback: @convention(c) (
    GhosttyTerminal?,
    UnsafeMutableRawPointer?
) -> Void = { _, _ in }
let ghosttyVTColorSchemeCallback: @convention(c) (
    GhosttyTerminal?,
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<GhosttyColorScheme>?
) -> Bool = { _, userdata, outScheme in
    guard let userdata, let outScheme else { return false }
    let box = Unmanaged<GhosttyVTCallbackBox>.fromOpaque(userdata).takeUnretainedValue()
    outScheme.pointee = box.colorScheme
    return true
}

func emptyStyle() -> GhosttyStyle {
    var style = GhosttyStyle()
    style.size = MemoryLayout<GhosttyStyle>.size
    return style
}

extension GhosttyColorRgb {
    init(_ color: GhosttyTerminalColor) {
        self.init(r: color.red, g: color.green, b: color.blue)
    }

    init(packed: UInt32) {
        self.init(
            r: UInt8((packed >> 16) & 0xFF),
            g: UInt8((packed >> 8) & 0xFF),
            b: UInt8(packed & 0xFF)
        )
    }

    var packed: UInt32 {
        (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }
}

extension GhosttyTerminalColorScheme {
    var ghosttyColorScheme: GhosttyColorScheme {
        switch self {
        case .light:
            GHOSTTY_COLOR_SCHEME_LIGHT
        case .dark:
            GHOSTTY_COLOR_SCHEME_DARK
        }
    }
}

extension GhosttyRenderStateCursorVisualStyle {
    var renderCursorStyle: GhosttyTerminalCursorStyle {
        switch self {
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK:
            .block
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE:
            .underline
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR:
            .beam
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW:
            .hollowBlock
        default:
            .block
        }
    }
}
