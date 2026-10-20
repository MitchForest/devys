// Ported from the reference repo's TerminalSurface host layer (P0-014).
// Maps NSEvent key events onto the canonical terminal key table
// (TerminalCore's GhosttyTerminalKey constants - one table, no local
// duplicate) and produces surface input commands.

import TerminalCore
import TerminalSurfaceCore

#if os(macOS)
    import AppKit

    enum TerminalMacInputAdapter {
        static func command(for event: NSEvent, text: String? = nil) -> TerminalSurfaceInputCommand? {
            guard let key = key(for: event.keyCode) else { return nil }
            return .key(GhosttyTerminalKeyEvent(
                key: key,
                action: event.isARepeat ? 2 : 1,
                text: sanitizedText(text ?? eventText(for: event)),
                modifiers: modifiers(for: event.modifierFlags),
                unshiftedCodepoint: unshiftedCodepoint(for: event)
            ))
        }

        static func keyUpCommand(for event: NSEvent) -> TerminalSurfaceInputCommand? {
            guard let key = key(for: event.keyCode) else { return nil }
            return .key(GhosttyTerminalKeyEvent(
                key: key,
                action: 0,
                text: nil,
                modifiers: modifiers(for: event.modifierFlags),
                unshiftedCodepoint: unshiftedCodepoint(for: event)
            ))
        }

        static func commandPaste(_ text: String) -> TerminalSurfaceInputCommand {
            .paste(text)
        }

        static func modifiers(for flags: NSEvent.ModifierFlags) -> GhosttyTerminalModifiers {
            var modifiers: GhosttyTerminalModifiers = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
            if flags.contains(.numericPad) { modifiers.insert(.numLock) }

            let rawFlags = flags.rawValue
            if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { modifiers.insert(.rightShift) }
            if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { modifiers.insert(.rightControl) }
            if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { modifiers.insert(.rightOption) }
            if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { modifiers.insert(.rightCommand) }
            return modifiers
        }

        static func key(for keyCode: UInt16) -> GhosttyTerminalKey? {
            keyByCode[keyCode]
        }

        private static func eventText(for event: NSEvent) -> String? {
            let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
            if flags.contains(.control) || flags.contains(.option) {
                return event.charactersIgnoringModifiers
            }
            return event.characters
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

        private static func unshiftedCodepoint(for event: NSEvent) -> UInt32 {
            guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return 0 }
            return scalar.value
        }

        private static let keyByCode: [UInt16: GhosttyTerminalKey] = [
            0x0032: .backquote,
            0x002a: .backslash,
            0x0021: .bracketLeft,
            0x001e: .bracketRight,
            0x002b: .comma,
            0x001d: .digit0,
            0x0012: .digit1,
            0x0013: .digit2,
            0x0014: .digit3,
            0x0015: .digit4,
            0x0017: .digit5,
            0x0016: .digit6,
            0x001a: .digit7,
            0x001c: .digit8,
            0x0019: .digit9,
            0x0018: .equal,
            0x000a: .intlBackslash,
            0x005e: .intlRo,
            0x005d: .intlYen,
            0x0000: .a,
            0x000b: .b,
            0x0008: .c,
            0x0002: .d,
            0x000e: .e,
            0x0003: .f,
            0x0005: .g,
            0x0004: .h,
            0x0022: .i,
            0x0026: .j,
            0x0028: .k,
            0x0025: .l,
            0x002e: .m,
            0x002d: .n,
            0x001f: .o,
            0x0023: .p,
            0x000c: .q,
            0x000f: .r,
            0x0001: .s,
            0x0011: .t,
            0x0020: .u,
            0x0009: .v,
            0x000d: .w,
            0x0007: .x,
            0x0010: .y,
            0x0006: .z,
            0x001b: .minus,
            0x002f: .period,
            0x0027: .quote,
            0x0029: .semicolon,
            0x002c: .slash,
            0x003a: .altLeft,
            0x003d: .altRight,
            0x0033: .backspace,
            0x0039: .capsLock,
            0x006e: .contextMenu,
            0x003b: .controlLeft,
            0x003e: .controlRight,
            0x0024: .enter,
            0x004c: .numpadEnter,
            0x0037: .metaLeft,
            0x0036: .metaRight,
            0x0038: .shiftLeft,
            0x003c: .shiftRight,
            0x0031: .space,
            0x0030: .tab,
            0x0075: .delete,
            0x0077: .end,
            0x0073: .home,
            0x0072: .insert,
            0x0079: .pageDown,
            0x0074: .pageUp,
            0x007d: .arrowDown,
            0x007b: .arrowLeft,
            0x007c: .arrowRight,
            0x007e: .arrowUp,
            0x0047: .numLock,
            0x0052: .numpad0,
            0x0053: .numpad1,
            0x0054: .numpad2,
            0x0055: .numpad3,
            0x0056: .numpad4,
            0x0057: .numpad5,
            0x0058: .numpad6,
            0x0059: .numpad7,
            0x005b: .numpad8,
            0x005c: .numpad9,
            0x0045: .numpadAdd,
            0x005f: .numpadComma,
            0x0041: .numpadDecimal,
            0x004b: .numpadDivide,
            0x0051: .numpadEqual,
            0x0043: .numpadMultiply,
            0x004e: .numpadSubtract,
            0x0035: .escape,
            0x007a: .f1,
            0x0078: .f2,
            0x0063: .f3,
            0x0076: .f4,
            0x0060: .f5,
            0x0061: .f6,
            0x0062: .f7,
            0x0064: .f8,
            0x0065: .f9,
            0x006d: .f10,
            0x0067: .f11,
            0x006f: .f12
        ]
    }
#endif
