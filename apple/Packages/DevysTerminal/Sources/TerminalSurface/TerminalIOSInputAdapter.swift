// Net-new for P0-014: the reference repo had no iOS terminal host.
// Pure mapping layer for the iOS host view: USB HID keyboard usages
// (UIKey.keyCode raw values) and UIKeyModifierFlags raw values onto the
// canonical terminal key table, plus software-keyboard text-to-command
// encoding. P0-045 adds the touch-interaction models: selection-handle
// geometry and anchoring, pinch font-size snapping, and Reduced Motion
// drive-mode selection. Deliberately UIKit-free so all of it is
// exercised by the package test run on macOS.

import CoreGraphics
import TerminalCore
import TerminalSurfaceCore
import TerminalVT

enum TerminalIOSInputAdapter {
    // UIKeyModifierFlags raw values (stable public constants).
    private static let shiftFlag = 1 << 17
    private static let controlFlag = 1 << 18
    private static let alternateFlag = 1 << 19
    private static let commandFlag = 1 << 20
    private static let alphaShiftFlag = 1 << 16
    private static let numericPadFlag = 1 << 21

    /// Hardware key press (UIKit `pressesBegan`/`pressesEnded`) to input
    /// command. `hidUsage` is `UIKey.keyCode.rawValue` (USB HID usage,
    /// keyboard page); `action` follows the ghostty convention
    /// (0 release, 1 press, 2 repeat).
    static func keyCommand(
        hidUsage: Int,
        characters: String,
        charactersIgnoringModifiers: String,
        modifierFlagsRawValue: Int,
        action: UInt8 = 1
    ) -> TerminalSurfaceInputCommand? {
        guard let key = key(forHIDUsage: hidUsage) else { return nil }
        let modifiers = modifiers(forFlagsRawValue: modifierFlagsRawValue)
        let text: String? = action == 0 ? nil : sanitizedText(
            modifiers.contains(.control) || modifiers.contains(.option)
                ? charactersIgnoringModifiers
                : characters
        )
        return .key(GhosttyTerminalKeyEvent(
            key: key,
            action: action,
            text: text,
            modifiers: modifiers,
            unshiftedCodepoint: charactersIgnoringModifiers.unicodeScalars.first?.value ?? 0
        ))
    }

    /// Software-keyboard insertion (`UIKeyInput.insertText`). Newlines
    /// become the enter key; single characters ride the key encoder with
    /// their text (mapped to a physical key when the character has one);
    /// multi-character insertions (dictation, marked-text commits) are
    /// routed as paste so the byte stream stays atomic.
    static func insertTextCommand(_ text: String) -> TerminalSurfaceInputCommand? {
        guard !text.isEmpty else { return nil }
        if text == "\n" || text == "\r" {
            return .key(GhosttyTerminalKeyEvent(key: .enter))
        }
        if text.count == 1, let scalar = text.unicodeScalars.first, text.unicodeScalars.count == 1 {
            let key = key(forCharacter: Character(text)) ?? .unidentified
            return .key(GhosttyTerminalKeyEvent(
                key: key,
                text: text,
                unshiftedCodepoint: scalar.value
            ))
        }
        return .paste(text)
    }

    /// Software-keyboard backspace (`UIKeyInput.deleteBackward`).
    static func deleteBackwardCommand() -> TerminalSurfaceInputCommand {
        .key(GhosttyTerminalKeyEvent(key: .backspace))
    }

    /// The accessory-bar interrupt: Ctrl-C.
    static func interruptCommand() -> TerminalSurfaceInputCommand {
        .key(GhosttyTerminalKeyEvent(
            key: .c,
            text: nil,
            modifiers: .control,
            unshiftedCodepoint: 99
        ))
    }

    static func escapeCommand() -> TerminalSurfaceInputCommand {
        .key(GhosttyTerminalKeyEvent(key: .escape))
    }

    static func tabCommand() -> TerminalSurfaceInputCommand {
        .key(GhosttyTerminalKeyEvent(key: .tab))
    }

    static func arrowUpCommand() -> TerminalSurfaceInputCommand {
        .key(GhosttyTerminalKeyEvent(key: .arrowUp))
    }

    static func arrowDownCommand() -> TerminalSurfaceInputCommand {
        .key(GhosttyTerminalKeyEvent(key: .arrowDown))
    }

    static func modifiers(forFlagsRawValue rawValue: Int) -> GhosttyTerminalModifiers {
        var modifiers: GhosttyTerminalModifiers = []
        if rawValue & shiftFlag != 0 { modifiers.insert(.shift) }
        if rawValue & controlFlag != 0 { modifiers.insert(.control) }
        if rawValue & alternateFlag != 0 { modifiers.insert(.option) }
        if rawValue & commandFlag != 0 { modifiers.insert(.command) }
        if rawValue & alphaShiftFlag != 0 { modifiers.insert(.capsLock) }
        if rawValue & numericPadFlag != 0 { modifiers.insert(.numLock) }
        return modifiers
    }

    private static func sanitizedText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let scalars = text.unicodeScalars
        guard let first = scalars.first,
              scalars.index(after: scalars.startIndex) == scalars.endIndex else {
            return text
        }
        guard first.value >= 0x20,
              first.value != 0x7F,
              !(0xF700...0xF8FF).contains(first.value)
        else {
            return nil
        }
        return text
    }

    static func key(forCharacter character: Character) -> GhosttyTerminalKey? {
        if let lowercased = character.lowercased().first,
           let letter = letterKeys[lowercased] {
            return letter
        }
        return characterKeys[character]
    }

    private static let letterKeys: [Character: GhosttyTerminalKey] = [
        "a": .a, "b": .b, "c": .c, "d": .d, "e": .e, "f": .f, "g": .g,
        "h": .h, "i": .i, "j": .j, "k": .k, "l": .l, "m": .m, "n": .n,
        "o": .o, "p": .p, "q": .q, "r": .r, "s": .s, "t": .t, "u": .u,
        "v": .v, "w": .w, "x": .x, "y": .y, "z": .z
    ]

    private static let characterKeys: [Character: GhosttyTerminalKey] = [
        "0": .digit0, "1": .digit1, "2": .digit2, "3": .digit3, "4": .digit4,
        "5": .digit5, "6": .digit6, "7": .digit7, "8": .digit8, "9": .digit9,
        " ": .space,
        "`": .backquote,
        "-": .minus,
        "=": .equal,
        "[": .bracketLeft,
        "]": .bracketRight,
        "\\": .backslash,
        ";": .semicolon,
        "'": .quote,
        ",": .comma,
        ".": .period,
        "/": .slash,
        "\t": .tab
    ]

    static func key(forHIDUsage usage: Int) -> GhosttyTerminalKey? {
        keyByHIDUsage[usage]
    }

    /// USB HID keyboard usage page (0x07) - the raw values behind
    /// `UIKeyboardHIDUsage.keyboard*`.
    private static let keyByHIDUsage: [Int: GhosttyTerminalKey] = [
        4: .a, 5: .b, 6: .c, 7: .d, 8: .e, 9: .f, 10: .g, 11: .h,
        12: .i, 13: .j, 14: .k, 15: .l, 16: .m, 17: .n, 18: .o, 19: .p,
        20: .q, 21: .r, 22: .s, 23: .t, 24: .u, 25: .v, 26: .w, 27: .x,
        28: .y, 29: .z,
        30: .digit1, 31: .digit2, 32: .digit3, 33: .digit4, 34: .digit5,
        35: .digit6, 36: .digit7, 37: .digit8, 38: .digit9, 39: .digit0,
        40: .enter,
        41: .escape,
        42: .backspace,
        43: .tab,
        44: .space,
        45: .minus,
        46: .equal,
        47: .bracketLeft,
        48: .bracketRight,
        49: .backslash,
        51: .semicolon,
        52: .quote,
        53: .backquote,
        54: .comma,
        55: .period,
        56: .slash,
        57: .capsLock,
        58: .f1, 59: .f2, 60: .f3, 61: .f4, 62: .f5, 63: .f6,
        64: .f7, 65: .f8, 66: .f9, 67: .f10, 68: .f11, 69: .f12,
        73: .insert,
        74: .home,
        75: .pageUp,
        76: .delete,
        77: .end,
        78: .pageDown,
        79: .arrowRight,
        80: .arrowLeft,
        81: .arrowDown,
        82: .arrowUp,
        83: .numLock,
        84: .numpadDivide,
        85: .numpadMultiply,
        86: .numpadSubtract,
        87: .numpadAdd,
        88: .numpadEnter,
        89: .numpad1, 90: .numpad2, 91: .numpad3, 92: .numpad4,
        93: .numpad5, 94: .numpad6, 95: .numpad7, 96: .numpad8,
        97: .numpad9, 98: .numpad0,
        99: .numpadDecimal,
        100: .intlBackslash,
        103: .numpadEqual,
        133: .numpadComma,
        135: .intlRo,
        137: .intlYen,
        224: .controlLeft,
        225: .shiftLeft,
        226: .altLeft,
        227: .metaLeft,
        228: .controlRight,
        229: .shiftRight,
        230: .altRight,
        231: .metaRight
    ]
}

// MARK: - Touch selection, pinch-to-resize, drive mode (P0-045)

extension TerminalIOSInputAdapter {
    enum SelectionHandle: Equatable {
        case start
        case end
    }

    /// The pinch range: 10-20pt, snapped to whole point sizes.
    static let fontSizeRange: ClosedRange<CGFloat> = 10...20

    static let selectionCaretWidth: CGFloat = 2

    /// Pinch scaling relative to the size at gesture start, snapped to
    /// integer point sizes and clamped to the supported range.
    static func pinchedFontSize(base: CGFloat, scale: CGFloat) -> CGFloat {
        min(max((base * scale).rounded(), fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// The scheduler seam: Reduced Motion swaps the display-link drive
    /// for on-demand drawing (and back, live, without a remount).
    static func driveConfiguration(reduceMotionEnabled: Bool) -> GhosttyTerminalMetalViewConfiguration {
        reduceMotionEnabled ? .onDemand : .displayLink
    }

    /// The MTKView pause state resolved from drive mode and visibility:
    /// the display link runs only while the surface is visible; the
    /// on-demand mode stays paused (the draw scheduler paints).
    static func metalViewIsPaused(
        configuration: GhosttyTerminalMetalViewConfiguration,
        isSurfaceVisible: Bool
    ) -> Bool {
        configuration.isPaused || !isSurfaceVisible
    }

    /// Grabbing a handle anchors the opposite endpoint for the whole
    /// drag, so dragging one handle across the other flips the selection
    /// naturally instead of collapsing it.
    static func selectionAnchor(
        forGrabbedHandle handle: SelectionHandle,
        in range: TerminalSelectionRange
    ) -> TerminalSelectionPoint {
        let normalized = normalizedSelectionRange(range)
        return handle == .start ? normalized.end : normalized.start
    }

    /// Long-press drags extend from the initially selected word: moving
    /// before the word anchors its end, moving past it anchors its start.
    static func selectionAnchor(
        forWordRange wordRange: TerminalSelectionRange,
        extendingToRow row: Int,
        col: Int
    ) -> TerminalSelectionPoint {
        let normalized = normalizedSelectionRange(wordRange)
        let beforeWord = row < normalized.start.row
            || (row == normalized.start.row && col < normalized.start.col)
        return beforeWord ? normalized.end : normalized.start
    }

    /// Caret bars at the selection edges in grid/content coordinates:
    /// the start caret hugs the leading edge of the first selected cell,
    /// the end caret the trailing edge of the last one.
    static func selectionCaretRects(
        for range: TerminalSelectionRange,
        metrics: GhosttyTerminalGridMetrics
    ) -> (start: CGRect, end: CGRect) {
        let normalized = normalizedSelectionRange(range)
        let startCell = metrics.rect(
            row: max(0, min(metrics.rows - 1, normalized.start.row)),
            colStart: max(0, min(metrics.cols - 1, normalized.start.col)),
            colEnd: max(0, min(metrics.cols - 1, normalized.start.col))
        )
        let endCell = metrics.rect(
            row: max(0, min(metrics.rows - 1, normalized.end.row)),
            colStart: max(0, min(metrics.cols - 1, normalized.end.col)),
            colEnd: max(0, min(metrics.cols - 1, normalized.end.col))
        )
        return (
            CGRect(
                x: startCell.minX - selectionCaretWidth / 2,
                y: startCell.minY,
                width: selectionCaretWidth,
                height: startCell.height
            ),
            CGRect(
                x: endCell.maxX - selectionCaretWidth / 2,
                y: endCell.minY,
                width: selectionCaretWidth,
                height: endCell.height
            )
        )
    }

    /// Which handle a touch grabs: the nearer caret center within the
    /// slop radius, so fat-finger touches near either end still pick the
    /// intended handle. `nil` means the touch is a scrollback pan.
    static func grabbedHandle(
        at point: CGPoint,
        startCaret: CGRect,
        endCaret: CGRect,
        grabRadius: CGFloat
    ) -> SelectionHandle? {
        let startDistance = squaredDistance(from: point, toCenterOf: startCaret)
        let endDistance = squaredDistance(from: point, toCenterOf: endCaret)
        let radius = grabRadius * grabRadius
        guard min(startDistance, endDistance) <= radius else { return nil }
        return startDistance <= endDistance ? .start : .end
    }

    private static func squaredDistance(from point: CGPoint, toCenterOf rect: CGRect) -> CGFloat {
        let deltaX = point.x - rect.midX
        let deltaY = point.y - rect.midY
        return deltaX * deltaX + deltaY * deltaY
    }
}
