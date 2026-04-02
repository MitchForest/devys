import Foundation
import ServerProtocol
import TerminalCore
import UIKit

extension IOSClientConnectionStore {
    func clearTerminalOutput() {
        sshTerminalSession.clearOutputPreview()
    }

    func sendHardwareInput(_ input: TerminalInput) {
        clearModifierLatches()
        sendInput(input, source: .keyboard, shouldApplyLatchedModifiers: false)
    }

    func sendSpecialKey(_ key: TerminalSpecialKey) {
        let input: TerminalInput
        switch key {
        case .escape:
            input = .escape
        case .tab:
            input = .tab
        case .up:
            input = .arrow(.up, appCursorMode: sshTerminalSession.appCursorMode)
        case .down:
            input = .arrow(.down, appCursorMode: sshTerminalSession.appCursorMode)
        case .left:
            input = .arrow(.left, appCursorMode: sshTerminalSession.appCursorMode)
        case .right:
            input = .arrow(.right, appCursorMode: sshTerminalSession.appCursorMode)
        case .pageUp:
            input = .pageUp
        case .pageDown:
            input = .pageDown
        case .home:
            input = .home(appCursorMode: sshTerminalSession.appCursorMode)
        case .end:
            input = .end(appCursorMode: sshTerminalSession.appCursorMode)
        case .enter:
            input = .enter
        case .backspace:
            input = .backspace
        case .interrupt:
            input = .interrupt
        }
        sendInput(input, source: .keyboard)
    }

    func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        Task {
            do {
                try await sshTerminalSession.sendPasteText(text)
            } catch {
                state = .failed("Paste failed: \(error.localizedDescription)")
            }
        }
    }

    func copySelectionOrScreenToClipboard() {
        Task {
            let selected = await sshTerminalSession.selectionText()
            let copied: String
            if let selected {
                copied = selected
            } else {
                copied = await sshTerminalSession.screenText()
            }
            guard !copied.isEmpty else { return }
            UIPasteboard.general.string = copied
        }
    }

    func toggleCtrlLatch() {
        isCtrlLatched.toggle()
    }

    func toggleAltLatch() {
        isAltLatched.toggle()
    }

    func clearModifierLatches() {
        isCtrlLatched = false
        isAltLatched = false
    }

    func beginSelection(row: Int, col: Int) {
        Task {
            await sshTerminalSession.beginSelection(row: row, col: col)
        }
    }

    func updateSelection(row: Int, col: Int) {
        Task {
            await sshTerminalSession.updateSelection(row: row, col: col)
        }
    }

    func finishSelection() {
        Task {
            await sshTerminalSession.finishSelection()
        }
    }

    func selectWord(row: Int, col: Int) {
        Task {
            await sshTerminalSession.selectWord(row: row, col: col)
        }
    }

    func clearSelection() {
        Task {
            await sshTerminalSession.clearSelection()
        }
    }

    func scrollViewport(lines: Int) {
        guard lines != 0 else { return }
        Task {
            if lines < 0 {
                await sshTerminalSession.scrollViewUp(abs(lines), allowAltScreen: true)
            } else {
                await sshTerminalSession.scrollViewDown(lines, allowAltScreen: true)
            }
        }
    }

    func scrollToTop() {
        Task {
            await sshTerminalSession.scrollToTop(allowAltScreen: true)
        }
    }

    func scrollToBottom() {
        Task {
            await sshTerminalSession.scrollToBottom(allowAltScreen: true)
        }
    }

    func sessionPickerLabel(for session: SessionSummary) -> String {
        let shortID = String(session.id.prefix(8))
        let status = session.status.rawValue
        let time = Self.sessionTimeFormatter.string(from: session.updatedAt)
        if let workspace = session.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !workspace.isEmpty {
            let repoHint = URL(fileURLWithPath: workspace).lastPathComponent
            return "\(shortID)  \(status)  \(repoHint)  \(time)"
        }
        return "\(shortID)  \(status)  \(time)"
    }

    private func sendInput(
        _ input: TerminalInput,
        source: TerminalInputSource,
        shouldApplyLatchedModifiers: Bool = true
    ) {
        Task {
            do {
                let encoded = shouldApplyLatchedModifiers ? try applyLatchedModifiers(to: input) : input
                try await sshTerminalSession.sendInput(encoded, source: source)
            } catch {
                state = .failed("Terminal input failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyLatchedModifiers(to input: TerminalInput) throws -> TerminalInput {
        var output = input

        if isCtrlLatched {
            switch output {
            case .text(let text) where text.count == 1:
                if let char = text.first, let controlInput = TerminalInput.ctrl(char) {
                    output = controlInput
                }
            default:
                break
            }
        }

        if isAltLatched {
            output = output.withAlt()
        }

        clearModifierLatches()
        return output
    }

    private static let sessionTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
