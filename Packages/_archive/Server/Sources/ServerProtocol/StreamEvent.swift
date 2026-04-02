import Foundation

public struct StreamEventEnvelope: Codable, Sendable, Equatable, Identifiable {
    public enum EventType: String, Codable, Sendable {
        case welcome
        case heartbeat
        case info
        case error
        case terminalExit = "terminal.exit"
        case terminalStatus = "terminal.status"
        case terminalOpened = "terminal.opened"
        case terminalOutput = "terminal.output"
        case terminalResized = "terminal.resized"
        case terminalClosed = "terminal.closed"
    }

    public let seq: UInt64
    public let type: EventType
    public let timestamp: Date
    public let sessionID: String?
    public let payload: JSONValue?

    enum CodingKeys: String, CodingKey {
        case seq
        case type
        case timestamp
        case sessionID = "sessionId"
        case payload
    }

    public var id: UInt64 { seq }
    public var message: String {
        textPayload?.message ?? ""
    }

    public init(
        seq: UInt64,
        type: EventType,
        timestamp: Date = .now,
        sessionID: String? = nil,
        payload: JSONValue? = nil
    ) {
        self.seq = seq
        self.type = type
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.payload = payload
    }

    public func decodePayload<T: Decodable>(_ type: T.Type) -> T? {
        guard let payload else { return nil }
        return try? ServerJSONCoding.decodeValue(type, from: payload)
    }

    public var textPayload: TextEventPayload? {
        decodePayload(TextEventPayload.self)
    }

    public var terminalExitPayload: TerminalExitPayload? {
        decodePayload(TerminalExitPayload.self)
    }

    public var terminalStatusPayload: TerminalStatusPayload? {
        decodePayload(TerminalStatusPayload.self)
    }

    public var terminalOpenedPayload: TerminalOpenedPayload? {
        decodePayload(TerminalOpenedPayload.self)
    }

    public var terminalOutputPayload: TerminalOutputPayload? {
        decodePayload(TerminalOutputPayload.self)
    }

    public var terminalResizedPayload: TerminalResizedPayload? {
        decodePayload(TerminalResizedPayload.self)
    }

    public var terminalClosedPayload: TerminalClosedPayload? {
        decodePayload(TerminalClosedPayload.self)
    }
}

public extension StreamEventEnvelope {
    static func text(
        seq: UInt64,
        type: EventType,
        message: String,
        sessionID: String? = nil,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: type,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(TextEventPayload(message: message))
        )
    }

    static func terminalExit(
        seq: UInt64,
        exitCode: Int,
        sessionID: String,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: .terminalExit,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(TerminalExitPayload(exitCode: exitCode))
        )
    }

    static func terminalStatus(
        seq: UInt64,
        status: TerminalSessionState,
        sessionID: String,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: .terminalStatus,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(TerminalStatusPayload(status: status))
        )
    }

    static func terminalOpened(
        seq: UInt64,
        terminalID: String,
        cols: Int,
        rows: Int,
        status: TerminalSessionState,
        sessionID: String,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: .terminalOpened,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(
                TerminalOpenedPayload(
                    terminalID: terminalID,
                    cols: cols,
                    rows: rows,
                    status: status
                )
            )
        )
    }

    static func terminalOutput(
        seq: UInt64,
        terminalID: String,
        stream: TerminalOutputStream,
        chunkBase64: String,
        byteCount: Int,
        sessionID: String,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: .terminalOutput,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(
                TerminalOutputPayload(
                    terminalID: terminalID,
                    stream: stream,
                    encoding: .base64,
                    chunk: chunkBase64,
                    byteCount: byteCount
                )
            )
        )
    }

    static func terminalResized(
        seq: UInt64,
        terminalID: String,
        cols: Int,
        rows: Int,
        source: TerminalResizeSource?,
        sessionID: String,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: .terminalResized,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(
                TerminalResizedPayload(
                    terminalID: terminalID,
                    cols: cols,
                    rows: rows,
                    source: source
                )
            )
        )
    }

    static func terminalClosed(
        seq: UInt64,
        terminalID: String,
        exitCode: Int?,
        reason: String?,
        sessionID: String,
        timestamp: Date = .now
    ) -> StreamEventEnvelope {
        StreamEventEnvelope(
            seq: seq,
            type: .terminalClosed,
            timestamp: timestamp,
            sessionID: sessionID,
            payload: try? ServerJSONCoding.encodeValue(
                TerminalClosedPayload(
                    terminalID: terminalID,
                    exitCode: exitCode,
                    reason: reason
                )
            )
        )
    }
}

public struct TextEventPayload: Codable, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct TerminalExitPayload: Codable, Sendable, Equatable {
    public let exitCode: Int

    public init(exitCode: Int) {
        self.exitCode = exitCode
    }
}

public enum TerminalSessionState: String, Codable, Sendable {
    case starting
    case running
    case idle
    case exited
}

public struct TerminalStatusPayload: Codable, Sendable, Equatable {
    public let status: TerminalSessionState

    public init(status: TerminalSessionState) {
        self.status = status
    }
}

public enum TerminalOutputStream: String, Codable, Sendable, CaseIterable {
    case stdout
    case stderr
}

public enum TerminalOutputEncoding: String, Codable, Sendable, CaseIterable {
    case base64
}

public struct TerminalOpenedPayload: Codable, Sendable, Equatable {
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

    public init(terminalID: String, cols: Int, rows: Int, status: TerminalSessionState) {
        self.terminalID = terminalID
        self.cols = cols
        self.rows = rows
        self.status = status
    }
}

public struct TerminalOutputPayload: Codable, Sendable, Equatable {
    public let terminalID: String
    public let stream: TerminalOutputStream
    public let encoding: TerminalOutputEncoding
    public let chunk: String
    public let byteCount: Int

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminalId"
        case stream
        case encoding
        case chunk
        case byteCount
    }

    public init(
        terminalID: String,
        stream: TerminalOutputStream,
        encoding: TerminalOutputEncoding = .base64,
        chunk: String,
        byteCount: Int
    ) {
        self.terminalID = terminalID
        self.stream = stream
        self.encoding = encoding
        self.chunk = chunk
        self.byteCount = byteCount
    }
}

public struct TerminalResizedPayload: Codable, Sendable, Equatable {
    public let terminalID: String
    public let cols: Int
    public let rows: Int
    public let source: TerminalResizeSource?

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminalId"
        case cols
        case rows
        case source
    }

    public init(terminalID: String, cols: Int, rows: Int, source: TerminalResizeSource? = nil) {
        self.terminalID = terminalID
        self.cols = cols
        self.rows = rows
        self.source = source
    }
}

public struct TerminalClosedPayload: Codable, Sendable, Equatable {
    public let terminalID: String
    public let exitCode: Int?
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminalId"
        case exitCode
        case reason
    }

    public init(terminalID: String, exitCode: Int? = nil, reason: String? = nil) {
        self.terminalID = terminalID
        self.exitCode = exitCode
        self.reason = reason
    }
}
