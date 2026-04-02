import Foundation
import ServerProtocol

public enum RemoteTerminalSessionError: Error, Sendable {
    case notConnected
    case invalidTerminalDimensions
    case missingSessionIdentity
}

public enum RemoteTerminalConnectionStatus: String, Sendable, Equatable {
    case connecting
    case connected
    case reconnecting
    case offline
    case failed

    public var label: String {
        switch self {
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .offline:
            return "Offline"
        case .failed:
            return "Failed"
        }
    }
}

public struct RemoteTerminalChromeState: Sendable, Equatable {
    public let title: String
    public let subtitle: String
    public let connectionStatus: RemoteTerminalConnectionStatus
    public let statusText: String
    public let canAttach: Bool
    public let canReconnect: Bool
    public let canSendInput: Bool
    public let canDisconnect: Bool
    public let canClearOutput: Bool
    public let lastError: String?

    public init(
        title: String,
        subtitle: String,
        connectionStatus: RemoteTerminalConnectionStatus,
        statusText: String,
        canAttach: Bool,
        canReconnect: Bool,
        canSendInput: Bool,
        canDisconnect: Bool,
        canClearOutput: Bool,
        lastError: String?
    ) {
        self.title = title
        self.subtitle = subtitle
        self.connectionStatus = connectionStatus
        self.statusText = statusText
        self.canAttach = canAttach
        self.canReconnect = canReconnect
        self.canSendInput = canSendInput
        self.canDisconnect = canDisconnect
        self.canClearOutput = canClearOutput
        self.lastError = lastError
    }
}

public struct RemoteTerminalTelemetry: Sendable, Equatable {
    public var attachCount: Int
    public var reconnectCount: Int
    public var staleCursorRecoveryCount: Int
    public var lastAttachLatencyMs: Int?
    public var firstByteLatencyMs: Int?

    public init(
        attachCount: Int = 0,
        reconnectCount: Int = 0,
        staleCursorRecoveryCount: Int = 0,
        lastAttachLatencyMs: Int? = nil,
        firstByteLatencyMs: Int? = nil
    ) {
        self.attachCount = attachCount
        self.reconnectCount = reconnectCount
        self.staleCursorRecoveryCount = staleCursorRecoveryCount
        self.lastAttachLatencyMs = lastAttachLatencyMs
        self.firstByteLatencyMs = firstByteLatencyMs
    }
}

public protocol RemoteTerminalTransport: Sendable {
    func createSession(
        baseURL: URL,
        workspacePath: String?
    ) async throws -> CreateSessionResponse

    func terminalAttach(
        baseURL: URL,
        sessionID: String,
        cols: Int,
        rows: Int,
        terminalID: String?,
        resumeCursor: UInt64?
    ) async throws -> TerminalAttachResponse

    func terminalInputBytes(
        baseURL: URL,
        sessionID: String,
        data: Data,
        source: TerminalInputSource?
    ) async throws -> TerminalInputBytesResponse

    func terminalResize(
        baseURL: URL,
        sessionID: String,
        cols: Int,
        rows: Int,
        source: TerminalResizeSource?
    ) async throws -> TerminalResizeResponse

    func terminalEvents(
        baseURL: URL,
        sessionID: String,
        cursor: UInt64
    ) async throws -> TerminalEventsResponse
}

extension ServerClient: RemoteTerminalTransport {}
