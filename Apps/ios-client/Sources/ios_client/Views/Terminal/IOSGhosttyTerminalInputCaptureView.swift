import GhosttyTerminalCore
import SwiftUI
import UIKit

enum IOSGhosttyTerminalHardwareInput: Equatable {
    case text(String)
    case special(GhosttyTerminalSpecialKey)
    case control(Character, withAlt: Bool)
    case altText(String)
}

struct IOSGhosttyTerminalInputCaptureView: UIViewRepresentable {
    @Binding var isFocused: Bool
    let onInput: (IOSGhosttyTerminalHardwareInput) -> Void

    func makeUIView(context: Context) -> IOSGhosttyTerminalHardwareInputView {
        let view = IOSGhosttyTerminalHardwareInputView()
        view.onInput = onInput
        return view
    }

    func updateUIView(_ uiView: IOSGhosttyTerminalHardwareInputView, context: Context) {
        uiView.onInput = onInput

        if isFocused {
            if uiView.isFirstResponder == false {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}

final class IOSGhosttyTerminalHardwareInputView: UIView, UIKeyInput, UITextInputTraits {
    var onInput: ((IOSGhosttyTerminalHardwareInput) -> Void)?

    var hasText: Bool { true }

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var keyboardType: UIKeyboardType = .asciiCapable
    var returnKeyType: UIReturnKeyType = .default
    var enablesReturnKeyAutomatically: Bool = false

    override var canBecomeFirstResponder: Bool { true }

    func insertText(_ text: String) {
        emit(.text(text))
    }

    func deleteBackward() {
        emit(.special(.backspace))
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDown)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight)),
            UIKeyCommand(input: UIKeyCommand.inputPageUp, modifierFlags: [], action: #selector(handlePageUp)),
            UIKeyCommand(input: UIKeyCommand.inputPageDown, modifierFlags: [], action: #selector(handlePageDown)),
            UIKeyCommand(input: UIKeyCommand.inputHome, modifierFlags: [], action: #selector(handleHome)),
            UIKeyCommand(input: UIKeyCommand.inputEnd, modifierFlags: [], action: #selector(handleEnd)),
            UIKeyCommand(input: UIKeyCommand.inputDelete, modifierFlags: [], action: #selector(handleDelete)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(handleBackTab))
        ]

        for input in Self.controlInputs {
            commands.append(
                UIKeyCommand(
                    input: input,
                    modifierFlags: [.control],
                    action: #selector(handleControl(_:))
                )
            )
            commands.append(
                UIKeyCommand(
                    input: input,
                    modifierFlags: [.control, .alternate],
                    action: #selector(handleControl(_:))
                )
            )
        }

        for input in Self.alternateInputs {
            commands.append(
                UIKeyCommand(
                    input: input,
                    modifierFlags: [.alternate],
                    action: #selector(handleAlternate(_:))
                )
            )
        }

        return commands
    }

    private static let controlInputs: [String] = {
        let letters = (97...122).compactMap { UnicodeScalar($0).map(String.init) }
        return letters + [" ", "["]
    }()

    private static let alternateInputs: [String] = {
        let letters = (97...122).compactMap { UnicodeScalar($0).map(String.init) }
        let digits = (48...57).compactMap { UnicodeScalar($0).map(String.init) }
        let punctuation = ["-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`"]
        return letters + digits + punctuation
    }()

    @objc private func handleControl(_ command: UIKeyCommand) {
        guard let input = command.input?.lowercased() else { return }
        let withAlt = command.modifierFlags.contains(.alternate)

        if input == " " {
            emit(.control(" ", withAlt: withAlt))
            return
        }

        if input == "[" {
            emit(.special(.escape))
            return
        }

        guard let character = input.first else { return }
        emit(.control(character, withAlt: withAlt))
    }

    @objc private func handleAlternate(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        emit(.altText(input))
    }

    @objc private func handleEscape() { emit(.special(.escape)) }
    @objc private func handleTab() { emit(.special(.tab)) }
    @objc private func handleBackTab() { emit(.special(.backtab)) }
    @objc private func handleUp() { emit(.special(.up)) }
    @objc private func handleDown() { emit(.special(.down)) }
    @objc private func handleLeft() { emit(.special(.left)) }
    @objc private func handleRight() { emit(.special(.right)) }
    @objc private func handlePageUp() { emit(.special(.pageUp)) }
    @objc private func handlePageDown() { emit(.special(.pageDown)) }
    @objc private func handleHome() { emit(.special(.home)) }
    @objc private func handleEnd() { emit(.special(.end)) }
    @objc private func handleDelete() { emit(.special(.delete)) }

    private func emit(_ input: IOSGhosttyTerminalHardwareInput) {
        onInput?(input)
    }
}
