import Foundation

public extension RemoteTerminalSession {
    var stateDescription: String {
        chromeState.statusText
    }

    var appCursorMode: Bool {
        latestRenderUpdate?.appCursorMode ?? false
    }

    var bracketedPasteMode: Bool {
        latestRenderUpdate?.bracketedPasteMode ?? false
    }

    var chromeState: RemoteTerminalChromeState {
        let connectionStatus: RemoteTerminalConnectionStatus
        let statusText: String

        switch state {
        case .idle:
            connectionStatus = .offline
            statusText = connectionStatus.label
        case .attaching:
            connectionStatus = .connecting
            statusText = connectionStatus.label
        case .running:
            connectionStatus = .connected
            statusText = connectionStatus.label
        case .reconnecting:
            connectionStatus = .reconnecting
            statusText = connectionStatus.label
        case .failed(let message):
            connectionStatus = .failed
            statusText = "\(connectionStatus.label): \(message)"
        case .closed:
            connectionStatus = .offline
            statusText = "Closed"
        }

        let subtitle = "session: \(sessionID ?? "none")  terminal: \(terminalID)  size: \(cols)x\(rows)"
        let canAttach: Bool
        let canReconnect: Bool
        let canSendInput = state == .running
        let canDisconnect = state != .idle && state != .closed

        switch state {
        case .idle, .closed, .failed:
            canAttach = true
        case .attaching, .running, .reconnecting:
            canAttach = false
        }

        switch state {
        case .running, .closed, .failed:
            canReconnect = true
        case .idle, .attaching, .reconnecting:
            canReconnect = false
        }

        return RemoteTerminalChromeState(
            title: title,
            subtitle: subtitle,
            connectionStatus: connectionStatus,
            statusText: statusText,
            canAttach: canAttach,
            canReconnect: canReconnect,
            canSendInput: canSendInput,
            canDisconnect: canDisconnect,
            canClearOutput: !outputPreview.isEmpty,
            lastError: lastError
        )
    }
}
