import Foundation

#if canImport(GhosttyKit) && os(macOS)
import AppKit
import GhosttyKit

// Upstream parity reference:
// .deps/ghostty-src/macos/Sources/Ghostty/NSEvent+Extension.swift
extension NSEvent {
    func devysGhosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.mods = ghosttyMods(from: modifierFlags)
        keyEvent.consumed_mods = ghosttyMods(
            from: (translationMods ?? modifierFlags).subtracting([.control, .command])
        )

        keyEvent.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = codepoint.value
        }

        return keyEvent
    }

    var devysGhosttyCharacters: String? {
        guard let characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }

            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}

func ghosttyEventModifierFlags(
    from mods: ghostty_input_mods_e
) -> NSEvent.ModifierFlags {
    var flags = NSEvent.ModifierFlags()

    if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 {
        flags.insert(.shift)
    }
    if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 {
        flags.insert(.control)
    }
    if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 {
        flags.insert(.option)
    }
    if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 {
        flags.insert(.command)
    }
    if mods.rawValue & GHOSTTY_MODS_CAPS.rawValue != 0 {
        flags.insert(.capsLock)
    }

    return flags
}

func ghosttyModifierAction(for event: NSEvent) -> ghostty_input_action_e {
    let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch event.keyCode {
    case 0x39:
        return rawFlags.contains(.capsLock) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x38, 0x3C:
        return rawFlags.contains(.shift) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x3B, 0x3E:
        return rawFlags.contains(.control) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x3A, 0x3D:
        return rawFlags.contains(.option) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    case 0x37, 0x36:
        return rawFlags.contains(.command) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    default:
        return GHOSTTY_ACTION_RELEASE
    }
}

func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods = GHOSTTY_MODS_NONE.rawValue

    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    let rawFlags = flags.rawValue
    if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

    return ghostty_input_mods_e(mods)
}

func ghosttyMouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
    switch buttonNumber {
    case 0: return GHOSTTY_MOUSE_LEFT
    case 1: return GHOSTTY_MOUSE_RIGHT
    case 2: return GHOSTTY_MOUSE_MIDDLE
    case 3: return GHOSTTY_MOUSE_EIGHT
    case 4: return GHOSTTY_MOUSE_NINE
    case 5: return GHOSTTY_MOUSE_SIX
    case 6: return GHOSTTY_MOUSE_SEVEN
    case 7: return GHOSTTY_MOUSE_FOUR
    case 8: return GHOSTTY_MOUSE_FIVE
    case 9: return GHOSTTY_MOUSE_TEN
    case 10: return GHOSTTY_MOUSE_ELEVEN
    default: return GHOSTTY_MOUSE_UNKNOWN
    }
}
#endif
