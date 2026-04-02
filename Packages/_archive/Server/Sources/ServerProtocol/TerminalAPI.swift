import Foundation

public enum TerminalInputSource: String, Codable, Sendable, CaseIterable {
    case keyboard
    case paste
    case programmatic
}

public enum TerminalResizeSource: String, Codable, Sendable, CaseIterable {
    case window
    case rotation
    case reconnect
}

public struct TerminalDescriptor: Codable, Sendable, Equatable {
    public let terminalID: String
    public let cols: Int
    public let rows: Int
    public let status: TerminalSessionState

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminalId"
        case cols
        case rows
        case status
    }

    public init(terminalID: String = "main", cols: Int, rows: Int, status: TerminalSessionState) {
        self.terminalID = terminalID
        self.cols = cols
        self.rows = rows
        self.status = status
    }
}

public struct TerminalAttachRequest: Codable, Sendable, Equatable {
    public let cols: Int
    public let rows: Int
    public let terminalID: String?
    public let resumeCursor: UInt64?

    enum CodingKeys: String, CodingKey {
        case cols
        case rows
        case terminalID = "terminalId"
        case resumeCursor
    }

    public init(cols: Int, rows: Int, terminalID: String? = nil, resumeCursor: UInt64? = nil) {
        self.cols = cols
        self.rows = rows
        self.terminalID = terminalID
        self.resumeCursor = resumeCursor
    }
}

public struct TerminalAttachResponse: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let session: SessionSummary
    public let terminal: TerminalDescriptor
    public let nextCursor: UInt64

    public init(
        accepted: Bool,
        session: SessionSummary,
        terminal: TerminalDescriptor,
        nextCursor: UInt64
    ) {
        self.accepted = accepted
        self.session = session
        self.terminal = terminal
        self.nextCursor = nextCursor
    }
}

public struct TerminalInputBytesRequest: Codable, Sendable, Equatable {
    public let bytesBase64: String
    public let source: TerminalInputSource?

    public init(bytesBase64: String, source: TerminalInputSource? = nil) {
        self.bytesBase64 = bytesBase64
        self.source = source
    }
}

public struct TerminalInputBytesResponse: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let session: SessionSummary
    public let terminal: TerminalDescriptor

    public init(accepted: Bool, session: SessionSummary, terminal: TerminalDescriptor) {
        self.accepted = accepted
        self.session = session
        self.terminal = terminal
    }
}

public struct TerminalResizeRequest: Codable, Sendable, Equatable {
    public let cols: Int
    public let rows: Int
    public let source: TerminalResizeSource?

    public init(cols: Int, rows: Int, source: TerminalResizeSource? = nil) {
        self.cols = cols
        self.rows = rows
        self.source = source
    }
}

public struct TerminalResizeResponse: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let session: SessionSummary
    public let terminal: TerminalDescriptor

    public init(accepted: Bool, session: SessionSummary, terminal: TerminalDescriptor) {
        self.accepted = accepted
        self.session = session
        self.terminal = terminal
    }
}

public struct TerminalEventsResponse: Codable, Sendable, Equatable {
    public let sessionID: String
    public let terminalID: String
    public let nextCursor: UInt64
    public let events: [StreamEventEnvelope]

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case terminalID = "terminalId"
        case nextCursor
        case events
    }

    public init(
        sessionID: String,
        terminalID: String,
        nextCursor: UInt64,
        events: [StreamEventEnvelope]
    ) {
        self.sessionID = sessionID
        self.terminalID = terminalID
        self.nextCursor = nextCursor
        self.events = events
    }
}
