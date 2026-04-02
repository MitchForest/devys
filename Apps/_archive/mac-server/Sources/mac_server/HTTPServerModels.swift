import Foundation
import Network
import ServerProtocol

enum RequestParseResult {
    case needMoreData
    case invalid
    case request(HTTPRequest)
}

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    var pathComponents: [String] {
        path.split(separator: "/").map(String.init)
    }

    var bearerAuthorizationToken: String? {
        guard let value = headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        let prefix = "Bearer "
        guard value.count > prefix.count, value.lowercased().hasPrefix(prefix.lowercased()) else {
            return nil
        }
        return String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

struct APIErrorResponse: Codable, Sendable {
    let code: String
    let message: String
    let details: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
    }

    init(code: String, message: String, details: [String: JSONValue]?) {
        self.code = code
        self.message = message
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        details = try container.decodeIfPresent([String: JSONValue].self, forKey: .details)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(details, forKey: .details)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension UInt8 {
    var isASCIIDigit: Bool {
        self >= 48 && self <= 57
    }
}

struct PersistedRunSession: Codable, Sendable {
    let id: String
    let createdAt: Date
    let workspacePath: String?
    let updatedAt: Date
    let status: SessionStatus
    let tmuxSessionName: String?
    let usingTmux: Bool
    let awaitingExitMarker: Bool
    let lastCapturedPane: String
    let events: [StreamEventEnvelope]
    let nextSeq: UInt64
    let terminalID: String
    let terminalCols: Int
    let terminalRows: Int
    let terminalStatus: TerminalSessionState

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case workspacePath
        case updatedAt
        case status
        case tmuxSessionName
        case usingTmux
        case awaitingExitMarker
        case lastCapturedPane
        case events
        case nextSeq
        case terminalID = "terminalId"
        case terminalCols
        case terminalRows
        case terminalStatus
    }

    init(
        id: String,
        createdAt: Date,
        workspacePath: String?,
        updatedAt: Date,
        status: SessionStatus,
        tmuxSessionName: String?,
        usingTmux: Bool,
        awaitingExitMarker: Bool,
        lastCapturedPane: String,
        events: [StreamEventEnvelope],
        nextSeq: UInt64,
        terminalID: String,
        terminalCols: Int,
        terminalRows: Int,
        terminalStatus: TerminalSessionState
    ) {
        self.id = id
        self.createdAt = createdAt
        self.workspacePath = workspacePath
        self.updatedAt = updatedAt
        self.status = status
        self.tmuxSessionName = tmuxSessionName
        self.usingTmux = usingTmux
        self.awaitingExitMarker = awaitingExitMarker
        self.lastCapturedPane = lastCapturedPane
        self.events = events
        self.nextSeq = nextSeq
        self.terminalID = terminalID
        self.terminalCols = terminalCols
        self.terminalRows = terminalRows
        self.terminalStatus = terminalStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        status = try container.decode(SessionStatus.self, forKey: .status)
        tmuxSessionName = try container.decodeIfPresent(String.self, forKey: .tmuxSessionName)
        usingTmux = try container.decode(Bool.self, forKey: .usingTmux)
        awaitingExitMarker = try container.decode(Bool.self, forKey: .awaitingExitMarker)
        lastCapturedPane = try container.decode(String.self, forKey: .lastCapturedPane)
        events = try container.decode([StreamEventEnvelope].self, forKey: .events)
        nextSeq = try container.decode(UInt64.self, forKey: .nextSeq)
        terminalID = try container.decodeIfPresent(String.self, forKey: .terminalID) ?? "main"
        terminalCols = try container.decodeIfPresent(Int.self, forKey: .terminalCols) ?? 120
        terminalRows = try container.decodeIfPresent(Int.self, forKey: .terminalRows) ?? 40
        terminalStatus = try container.decodeIfPresent(TerminalSessionState.self, forKey: .terminalStatus) ?? .idle
    }
}

struct SessionStore: Sendable {
    private let directoryURL: URL

    init(baseDirectoryURL: URL? = nil) throws {
        if let baseDirectoryURL {
            self.directoryURL = baseDirectoryURL
        } else {
            self.directoryURL = try Self.defaultDirectoryURL()
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func save(session: PersistedRunSession) throws {
        let encoder = ServerJSONCoding.makeEncoder()
        let data = try encoder.encode(session)
        let fileURL = sessionFileURL(for: session.id)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadAll() throws -> [PersistedRunSession] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = ServerJSONCoding.makeDecoder()
        var sessions: [PersistedRunSession] = []
        let jsonURLs = urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in jsonURLs {
            do {
                let data = try Data(contentsOf: url)
                let session = try decoder.decode(PersistedRunSession.self, from: data)
                sessions.append(session)
            } catch {
                writeServerLog("skipping unreadable session state \(url.lastPathComponent): \(error)")
            }
        }
        return sessions
    }

    private func sessionFileURL(for sessionID: String) -> URL {
        directoryURL.appendingPathComponent("\(sessionID).json", isDirectory: false)
    }

    static func defaultDataRootURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["DEVYS_MAC_SERVER_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportURL
            .appendingPathComponent("devys", isDirectory: true)
            .appendingPathComponent("mac-server", isDirectory: true)
    }

    private static func defaultDirectoryURL() throws -> URL {
        try defaultDataRootURL().appendingPathComponent("sessions", isDirectory: true)
    }
}

final class RunSession: @unchecked Sendable {
    private static let maxBufferedEventCount = 8_000
    private static let maxBufferedEventBytes = 4 * 1024 * 1024

    let id: String
    let createdAt: Date
    let workspacePath: String?
    var updatedAt: Date
    var status: SessionStatus
    var tmuxSessionName: String?
    var usingTmux = false
    var awaitingExitMarker = false
    var lastCapturedPane = ""
    var tmuxOutputSession: TmuxControlSession?
    var tmuxOutputBuffer = Data()
    var tmuxExitMarkerCarry = Data()
    private(set) var terminalID = "main"
    private(set) var terminalCols = 120
    private(set) var terminalRows = 40
    private(set) var terminalStatus: TerminalSessionState = .idle
    var onStateChange: (() -> Void)?
    private(set) var events: [StreamEventEnvelope] = []
    private var nextSeq: UInt64 = 1
    private var bufferedEventBytes = 0
    private(set) var droppedEventCount: UInt64 = 0

    init(id: String, workspacePath: String?) {
        self.id = id
        self.workspacePath = workspacePath
        self.createdAt = .now
        self.updatedAt = .now
        self.status = .created
    }

    init(persistedState: PersistedRunSession) {
        self.id = persistedState.id
        self.createdAt = persistedState.createdAt
        self.workspacePath = persistedState.workspacePath
        self.updatedAt = persistedState.updatedAt
        self.status = persistedState.status
        self.tmuxSessionName = persistedState.tmuxSessionName
        self.usingTmux = persistedState.usingTmux
        self.awaitingExitMarker = persistedState.awaitingExitMarker
        self.lastCapturedPane = persistedState.lastCapturedPane
        self.terminalID = persistedState.terminalID
        self.terminalCols = persistedState.terminalCols
        self.terminalRows = persistedState.terminalRows
        self.terminalStatus = persistedState.terminalStatus
        self.events = persistedState.events
        self.bufferedEventBytes = persistedState.events.reduce(0) { partialResult, event in
            partialResult + Self.estimatedSize(of: event)
        }
        let minimumNext = (persistedState.events.last?.seq ?? 0) + 1
        self.nextSeq = max(persistedState.nextSeq, minimumNext)
        enforceEventRetentionPolicy()
    }

    var persistedState: PersistedRunSession {
        PersistedRunSession(
            id: id,
            createdAt: createdAt,
            workspacePath: workspacePath,
            updatedAt: updatedAt,
            status: status,
            tmuxSessionName: tmuxSessionName,
            usingTmux: usingTmux,
            awaitingExitMarker: awaitingExitMarker,
            lastCapturedPane: lastCapturedPane,
            events: events,
            nextSeq: nextSeq,
            terminalID: terminalID,
            terminalCols: terminalCols,
            terminalRows: terminalRows,
            terminalStatus: terminalStatus
        )
    }

    var summary: SessionSummary {
        SessionSummary(
            id: id,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            workspacePath: workspacePath
        )
    }

    var terminalDescriptor: TerminalDescriptor {
        TerminalDescriptor(
            terminalID: terminalID,
            cols: terminalCols,
            rows: terminalRows,
            status: terminalStatus
        )
    }

    func markStatus(_ status: SessionStatus) {
        self.status = status
        self.updatedAt = .now
        onStateChange?()
    }

    func appendText(type: StreamEventEnvelope.EventType, message: String) {
        append(
            .text(
                seq: nextSequence(),
                type: type,
                message: message,
                sessionID: id
            )
        )
    }

    func appendTerminalExit(exitCode: Int) {
        append(
            .terminalExit(
                seq: nextSequence(),
                exitCode: exitCode,
                sessionID: id
            )
        )
    }

    func appendTerminalStatus(_ status: TerminalSessionState) {
        terminalStatus = status
        append(
            .terminalStatus(
                seq: nextSequence(),
                status: status,
                sessionID: id
            )
        )
    }

    func appendTerminalOutput(chunk: Data, stream: TerminalOutputStream) {
        append(
            .terminalOutput(
                seq: nextSequence(),
                terminalID: terminalID,
                stream: stream,
                chunkBase64: chunk.base64EncodedString(),
                byteCount: chunk.count,
                sessionID: id
            )
        )
    }

    func appendTerminalOpened() {
        append(
            .terminalOpened(
                seq: nextSequence(),
                terminalID: terminalID,
                cols: terminalCols,
                rows: terminalRows,
                status: terminalStatus,
                sessionID: id
            )
        )
    }

    func appendTerminalResized(source: TerminalResizeSource?) {
        append(
            .terminalResized(
                seq: nextSequence(),
                terminalID: terminalID,
                cols: terminalCols,
                rows: terminalRows,
                source: source,
                sessionID: id
            )
        )
    }

    func appendTerminalClosed(exitCode: Int?, reason: String?) {
        append(
            .terminalClosed(
                seq: nextSequence(),
                terminalID: terminalID,
                exitCode: exitCode,
                reason: reason,
                sessionID: id
            )
        )
    }

    func setTerminalID(_ terminalID: String) {
        self.terminalID = terminalID
        onStateChange?()
    }

    func setTerminalDimensions(cols: Int, rows: Int) {
        terminalCols = cols
        terminalRows = rows
        onStateChange?()
    }

    func markDirty() {
        onStateChange?()
    }

    func staleCursorDetails(for cursor: UInt64) -> [String: JSONValue]? {
        guard let firstEvent = events.first else { return nil }
        guard firstEvent.seq > 0 else { return nil }
        guard cursor < firstEvent.seq - 1 else { return nil }
        return [
            "sessionId": .string(id),
            "requestedCursor": .string(String(cursor)),
            "oldestAvailableCursor": .string(String(firstEvent.seq - 1)),
            "latestCursor": .string(String(max(nextSeq - 1, firstEvent.seq - 1))),
            "droppedEventCount": .string(String(droppedEventCount))
        ]
    }

    deinit {
        tmuxOutputSession?.stdout.readabilityHandler = nil
        tmuxOutputSession?.stderr.readabilityHandler = nil
        try? tmuxOutputSession?.stdin.close()
        if let process = tmuxOutputSession?.process, process.isRunning {
            process.terminate()
        }
        tmuxOutputSession = nil
    }

    private func append(_ event: StreamEventEnvelope) {
        events.append(event)
        bufferedEventBytes += Self.estimatedSize(of: event)
        updatedAt = .now
        enforceEventRetentionPolicy()
        onStateChange?()
    }

    private func nextSequence() -> UInt64 {
        defer { nextSeq += 1 }
        return nextSeq
    }

    private func enforceEventRetentionPolicy() {
        guard !events.isEmpty else {
            bufferedEventBytes = 0
            return
        }

        while events.count > Self.maxBufferedEventCount || bufferedEventBytes > Self.maxBufferedEventBytes {
            let removed = events.removeFirst()
            bufferedEventBytes = max(0, bufferedEventBytes - Self.estimatedSize(of: removed))
            droppedEventCount += 1
        }
    }

    private static func estimatedSize(of event: StreamEventEnvelope) -> Int {
        switch event.type {
        case .terminalOutput:
            return event.terminalOutputPayload?.byteCount ?? 0
        case .terminalExit:
            return 32
        case .terminalStatus:
            return 32
        case .terminalOpened:
            return 64
        case .terminalResized:
            return 64
        case .terminalClosed:
            return 64
        case .welcome, .heartbeat, .info, .error:
            return event.textPayload?.message.utf8.count ?? 32
        }
    }
}
