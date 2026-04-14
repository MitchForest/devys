import AppKit
import Testing
import GhosttyKit
@testable import GhosttyTerminal

@Suite("Ghostty Input Event Tests")
struct GhosttyInputEventTests {
    @Test("Private-use-area characters are not forwarded as terminal text")
    func privateUseAreaCharactersAreFiltered() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "\u{F700}",
                charactersIgnoringModifiers: "\u{F700}",
                isARepeat: false,
                keyCode: 126
            )
        )

        #expect(event.devysGhosttyCharacters == nil)
    }

    @Test("Control characters use untranslated printable text")
    func controlCharactersUsePrintableFallback() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "\u{03}",
                charactersIgnoringModifiers: "c",
                isARepeat: false,
                keyCode: 8
            )
        )

        #expect(event.devysGhosttyCharacters == "c")
    }

    @Test("Consumed modifiers strip command and control from translated text")
    func consumedModifiersStripCommandAndControl() throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control, .shift, .option],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "A",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )

        let keyEvent = event.devysGhosttyKeyEvent(
            GHOSTTY_ACTION_PRESS,
            translationMods: [.command, .control, .shift, .option]
        )

        #expect(keyEvent.mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0)
        #expect(keyEvent.mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0)
        #expect(keyEvent.consumed_mods.rawValue & GHOSTTY_MODS_SUPER.rawValue == 0)
        #expect(keyEvent.consumed_mods.rawValue & GHOSTTY_MODS_CTRL.rawValue == 0)
        #expect(keyEvent.consumed_mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0)
        #expect(keyEvent.consumed_mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
    }

    @Test("Modifier action detects right-side modifier presses")
    func modifierActionDetectsRightShiftPress() throws {
        let flags = NSEvent.ModifierFlags([
            .shift,
            NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))
        ])
        let event = try #require(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: flags,
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 0x3C
            )
        )

        #expect(ghosttyModifierAction(for: event) == GHOSTTY_ACTION_PRESS)
    }
}
