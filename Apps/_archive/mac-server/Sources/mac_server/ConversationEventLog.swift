import Foundation
import ServerProtocol

/// Append-only NDJSON event log for a single conversation session.
///
/// Each conversation has its own event log file. Events are appended atomically
/// and can be replayed from any cursor position. The log survives server restarts.
actor ConversationEventLog {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    private var latestSeq: UInt64 = 0
    private var cachedEvents: [ConversationEventEnvelope] = []
    private let encoder = ServerJSONCoding.makeEncoder()
    private let decoder = ServerJSONCoding.makeDecoder()

    deinit {
        try? fileHandle?.close()
    }

    init(directory: URL, sessionID: String) {
        self.fileURL = directory
            .appendingPathComponent(sessionID)
            .appendingPathComponent("events.ndjson")
    }

    // MARK: - Lifecycle

    /// Load existing events from disk and prepare for appending.
    func open() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let data = try Data(contentsOf: fileURL)
        cachedEvents = parseEvents(from: data)
        latestSeq = cachedEvents.last?.sequence ?? 0

        fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }

    // MARK: - Write

    /// Append an event with the next sequence number.
    func append(
        sessionID: String,
        type: ConversationEventType,
        payload: JSONValue? = nil
    ) throws -> ConversationEventEnvelope {
        latestSeq += 1
        let envelope = ConversationEventEnvelope(
            sessionID: sessionID,
            sequence: latestSeq,
            type: type,
            payload: payload
        )

        let data = try encoder.encode(envelope)
        guard var line = String(data: data, encoding: .utf8) else {
            throw EventLogError.encodingFailed
        }
        line += "\n"

        guard let lineData = line.data(using: .utf8) else {
            throw EventLogError.encodingFailed
        }

        fileHandle?.write(lineData)
        cachedEvents.append(envelope)

        return envelope
    }

    // MARK: - Read

    /// Replay events starting after the given sequence number.
    func replay(afterSequence cursor: UInt64) -> [ConversationEventEnvelope] {
        cachedEvents.filter { $0.sequence > cursor }
    }

    /// The latest sequence number.
    var currentSequence: UInt64 {
        latestSeq
    }

    // MARK: - Parsing

    private func parseEvents(from data: Data) -> [ConversationEventEnvelope] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ConversationEventEnvelope.self, from: lineData)
        }
    }
}

enum EventLogError: Error {
    case encodingFailed
}
