import SwiftUI
import TerminalCore
import UIKit

struct IOSTerminalInputCaptureView: UIViewRepresentable {
    @Binding var isFocused: Bool
    let appCursorMode: Bool
    let onInput: (TerminalInput) -> Void

    func makeUIView(context: Context) -> TerminalHardwareInputView {
        let view = TerminalHardwareInputView()
        view.appCursorMode = appCursorMode
        view.onInput = onInput
        return view
    }

    func updateUIView(_ uiView: TerminalHardwareInputView, context: Context) {
        uiView.appCursorMode = appCursorMode
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

final class TerminalHardwareInputView: UIView, UIKeyInput, UITextInputTraits {
    var appCursorMode = false
    var onInput: ((TerminalInput) -> Void)?

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
        emit(.backspace)
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
        let navigation = [
            "\t",
            UIKeyCommand.inputUpArrow,
            UIKeyCommand.inputDownArrow,
            UIKeyCommand.inputLeftArrow,
            UIKeyCommand.inputRightArrow,
            UIKeyCommand.inputPageUp,
            UIKeyCommand.inputPageDown,
            UIKeyCommand.inputHome,
            UIKeyCommand.inputEnd
        ]
        return letters + digits + punctuation + navigation
    }()

    @objc private func handleControl(_ command: UIKeyCommand) {
        guard let input = command.input else { return }
        let withAlt = command.modifierFlags.contains(.alternate)

        if input == " " {
            emit(.ctrlSpace, withAlt: withAlt)
            return
        }

        if input == "[" {
            emit(.escape, withAlt: withAlt)
            return
        }

        guard let character = input.lowercased().first, let controlInput = TerminalInput.ctrl(character) else { return }
        emit(controlInput, withAlt: withAlt)
    }

    @objc private func handleAlternate(_ command: UIKeyCommand) {
        guard let input = command.input else { return }

        if input == "\t" {
            emit(.backtab)
            return
        }

        switch input {
        case UIKeyCommand.inputUpArrow:
            emit(TerminalInput.arrow(.up, appCursorMode: appCursorMode), withAlt: true)
        case UIKeyCommand.inputDownArrow:
            emit(TerminalInput.arrow(.down, appCursorMode: appCursorMode), withAlt: true)
        case UIKeyCommand.inputLeftArrow:
            emit(TerminalInput.arrow(.left, appCursorMode: appCursorMode), withAlt: true)
        case UIKeyCommand.inputRightArrow:
            emit(TerminalInput.arrow(.right, appCursorMode: appCursorMode), withAlt: true)
        case UIKeyCommand.inputHome:
            emit(TerminalInput.home(appCursorMode: appCursorMode), withAlt: true)
        case UIKeyCommand.inputEnd:
            emit(TerminalInput.end(appCursorMode: appCursorMode), withAlt: true)
        case UIKeyCommand.inputPageUp:
            emit(.pageUp, withAlt: true)
        case UIKeyCommand.inputPageDown:
            emit(.pageDown, withAlt: true)
        default:
            emit(.text(input), withAlt: true)
        }
    }

    @objc private func handleEscape() {
        emit(.escape)
    }

    @objc private func handleTab() {
        emit(.tab)
    }

    @objc private func handleBackTab() {
        emit(.backtab)
    }

    @objc private func handleUp() {
        emit(TerminalInput.arrow(.up, appCursorMode: appCursorMode))
    }

    @objc private func handleDown() {
        emit(TerminalInput.arrow(.down, appCursorMode: appCursorMode))
    }

    @objc private func handleLeft() {
        emit(TerminalInput.arrow(.left, appCursorMode: appCursorMode))
    }

    @objc private func handleRight() {
        emit(TerminalInput.arrow(.right, appCursorMode: appCursorMode))
    }

    @objc private func handlePageUp() {
        emit(.pageUp)
    }

    @objc private func handlePageDown() {
        emit(.pageDown)
    }

    @objc private func handleHome() {
        emit(TerminalInput.home(appCursorMode: appCursorMode))
    }

    @objc private func handleEnd() {
        emit(TerminalInput.end(appCursorMode: appCursorMode))
    }

    @objc private func handleDelete() {
        emit(.delete)
    }

    private func emit(_ input: TerminalInput, withAlt: Bool = false) {
        onInput?(withAlt ? input.withAlt() : input)
    }
}
