import XCTest
import ServerProtocol
@testable import ServerClient

final class ServerClientTests: XCTestCase {
    func testDecodeEventLine() throws {
        let event = StreamEventEnvelope.text(seq: 42, type: .heartbeat, message: "tick")
        let data = try ServerJSONCoding.makeEncoder().encode(event)
        let line = String(decoding: data, as: UTF8.self)

        let decoded = try ServerClient.decodeEventLine(line)
        XCTAssertEqual(decoded.seq, 42)
        XCTAssertEqual(decoded.type, .heartbeat)
        XCTAssertEqual(decoded.message, "tick")
    }

    func testDecodeEventLineRejectsEmpty() {
        XCTAssertThrowsError(try ServerClient.decodeEventLine("   \n"))
    }

    func testEndpointBuilder() {
        let baseURL = URL(string: "http://100.64.0.10:8787")!
        let endpoint = ServerClient.endpoint(baseURL: baseURL, path: "health")
        XCTAssertEqual(endpoint.absoluteString, "http://100.64.0.10:8787/health")

        let capabilitiesEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "capabilities")
        XCTAssertEqual(capabilitiesEndpoint.absoluteString, "http://100.64.0.10:8787/capabilities")

        let pairingChallengeEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "pairing/challenge")
        XCTAssertEqual(pairingChallengeEndpoint.absoluteString, "http://100.64.0.10:8787/pairing/challenge")

        let pairingExchangeEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "pairing/exchange")
        XCTAssertEqual(pairingExchangeEndpoint.absoluteString, "http://100.64.0.10:8787/pairing/exchange")

        let pairingsEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "pairings")
        XCTAssertEqual(pairingsEndpoint.absoluteString, "http://100.64.0.10:8787/pairings")

        let rotatePairingEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "pairings/pairing-1/rotate")
        XCTAssertEqual(rotatePairingEndpoint.absoluteString, "http://100.64.0.10:8787/pairings/pairing-1/rotate")

        let revokePairingEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "pairings/pairing-1/revoke")
        XCTAssertEqual(revokePairingEndpoint.absoluteString, "http://100.64.0.10:8787/pairings/pairing-1/revoke")

        let commandProfilesEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "profiles")
        XCTAssertEqual(commandProfilesEndpoint.absoluteString, "http://100.64.0.10:8787/profiles")

        let validateCommandProfileEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "profiles/validate")
        XCTAssertEqual(
            validateCommandProfileEndpoint.absoluteString,
            "http://100.64.0.10:8787/profiles/validate"
        )

        let deleteCommandProfileEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "profiles/delete")
        XCTAssertEqual(deleteCommandProfileEndpoint.absoluteString, "http://100.64.0.10:8787/profiles/delete")

        let sessionsEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "sessions")
        XCTAssertEqual(sessionsEndpoint.absoluteString, "http://100.64.0.10:8787/sessions")

        let runEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "sessions/abc/run")
        XCTAssertEqual(runEndpoint.absoluteString, "http://100.64.0.10:8787/sessions/abc/run")

        let attachEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "sessions/abc/terminal/attach")
        XCTAssertEqual(attachEndpoint.absoluteString, "http://100.64.0.10:8787/sessions/abc/terminal/attach")

        let inputEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "sessions/abc/terminal/input")
        XCTAssertEqual(inputEndpoint.absoluteString, "http://100.64.0.10:8787/sessions/abc/terminal/input")

        let resizeEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "sessions/abc/terminal/resize")
        XCTAssertEqual(resizeEndpoint.absoluteString, "http://100.64.0.10:8787/sessions/abc/terminal/resize")

        let eventsEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "sessions/abc/terminal/events")
        XCTAssertEqual(eventsEndpoint.absoluteString, "http://100.64.0.10:8787/sessions/abc/terminal/events")

        let vNextSessionsEndpoint = ServerClient.endpoint(baseURL: baseURL, path: "v1/conversations/sessions")
        XCTAssertEqual(vNextSessionsEndpoint.absoluteString, "http://100.64.0.10:8787/v1/conversations/sessions")

        let vNextStreamEndpoint = ServerClient.endpoint(
            baseURL: baseURL,
            path: "v1/conversations/sessions/sess-1/stream"
        )
        XCTAssertEqual(
            vNextStreamEndpoint.absoluteString,
            "http://100.64.0.10:8787/v1/conversations/sessions/sess-1/stream"
        )
    }

    func testDecodeEventLineTerminalOutput() throws {
        let event = StreamEventEnvelope.terminalOutput(
            seq: 7,
            terminalID: "main",
            stream: .stdout,
            chunkBase64: "aGVsbG8K",
            byteCount: 6,
            sessionID: "session-1"
        )
        let data = try ServerJSONCoding.makeEncoder().encode(event)
        let line = String(decoding: data, as: UTF8.self)

        let decoded = try ServerClient.decodeEventLine(line)
        XCTAssertEqual(decoded.seq, 7)
        XCTAssertEqual(decoded.type, .terminalOutput)
        XCTAssertEqual(decoded.terminalOutputPayload?.terminalID, "main")
        XCTAssertEqual(decoded.terminalOutputPayload?.chunk, "aGVsbG8K")
    }

    @MainActor
    func testRemoteTerminalSessionConnectConsumesOutput() async throws {
        let baseURL = URL(string: "http://127.0.0.1:8787")!
        let sessionID = "session-remote-1"
        let output = "echo hello\n"
        let outputEvent = StreamEventEnvelope.terminalOutput(
            seq: 1,
            terminalID: "main",
            stream: .stdout,
            chunkBase64: Data(output.utf8).base64EncodedString(),
            byteCount: output.utf8.count,
            sessionID: sessionID
        )
        let transport = MockRemoteTerminalTransport(
            sessionID: sessionID,
            attachResponses: [
                makeAttachResponse(sessionID: sessionID, nextCursor: 0, cols: 120, rows: 40)
            ],
            eventResponses: [
                .success(
                    TerminalEventsResponse(
                        sessionID: sessionID,
                        terminalID: "main",
                        nextCursor: 2,
                        events: [outputEvent]
                    )
                )
            ]
        )
        let remote = RemoteTerminalSession(transport: transport, pollIntervalNanoseconds: 5_000_000)

        try await remote.connect(baseURL: baseURL, cols: 120, rows: 40)
        await waitUntil {
            remote.outputPreview.contains(output)
        }

        XCTAssertEqual(remote.state, .running)
        XCTAssertEqual(remote.sessionID, sessionID)
        XCTAssertTrue(remote.outputPreview.contains(output))
        XCTAssertEqual(remote.telemetry.attachCount, 1)
        XCTAssertNotNil(remote.telemetry.firstByteLatencyMs)
        remote.disconnect()
    }

    @MainActor
    func testRemoteTerminalSessionRecoversFromStaleCursor() async throws {
        let baseURL = URL(string: "http://127.0.0.1:8787")!
        let sessionID = "session-remote-stale"
        let transport = MockRemoteTerminalTransport(
            sessionID: sessionID,
            attachResponses: [
                makeAttachResponse(sessionID: sessionID, nextCursor: 0, cols: 120, rows: 40),
                makeAttachResponse(sessionID: sessionID, nextCursor: 10, cols: 120, rows: 40)
            ],
            eventResponses: [
                .failure(ServerClientError.badStatus(409)),
                .success(
                    TerminalEventsResponse(
                        sessionID: sessionID,
                        terminalID: "main",
                        nextCursor: 10,
                        events: []
                    )
                )
            ]
        )
        let remote = RemoteTerminalSession(transport: transport, pollIntervalNanoseconds: 5_000_000)

        try await remote.connect(baseURL: baseURL, cols: 120, rows: 40)
        await waitUntil {
            remote.telemetry.staleCursorRecoveryCount == 1 && remote.telemetry.attachCount == 2
        }

        XCTAssertEqual(remote.state, .running)
        XCTAssertEqual(remote.telemetry.staleCursorRecoveryCount, 1)
        let attachCalls = await transport.attachCalls()
        XCTAssertEqual(attachCalls.count, 2)
        XCTAssertNil(attachCalls[1].resumeCursor)
        remote.disconnect()
    }

    @MainActor
    func testRemoteTerminalSessionSendsInputAndResize() async throws {
        let baseURL = URL(string: "http://127.0.0.1:8787")!
        let sessionID = "session-remote-io"
        let transport = MockRemoteTerminalTransport(
            sessionID: sessionID,
            attachResponses: [
                makeAttachResponse(sessionID: sessionID, nextCursor: 0, cols: 120, rows: 40)
            ],
            eventResponses: []
        )
        let remote = RemoteTerminalSession(transport: transport, pollIntervalNanoseconds: 5_000_000)

        try await remote.connect(baseURL: baseURL, cols: 120, rows: 40)
        try await remote.sendText("pwd\n")
        try await remote.resize(cols: 140, rows: 50)

        let inputs = await transport.inputCalls()
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(String(decoding: inputs[0].data, as: UTF8.self), "pwd\n")
        XCTAssertEqual(inputs[0].source, .keyboard)

        let resizes = await transport.resizeCalls()
        XCTAssertEqual(resizes.count, 1)
        XCTAssertEqual(resizes[0].cols, 140)
        XCTAssertEqual(resizes[0].rows, 50)
        XCTAssertEqual(resizes[0].source, .window)
        remote.disconnect()
    }

    @MainActor
    func testRemoteTerminalSessionReconnectUsesExistingSession() async throws {
        let baseURL = URL(string: "http://127.0.0.1:8787")!
        let sessionID = "session-remote-reconnect"
        let transport = MockRemoteTerminalTransport(
            sessionID: sessionID,
            attachResponses: [
                makeAttachResponse(sessionID: sessionID, nextCursor: 0, cols: 120, rows: 40),
                makeAttachResponse(sessionID: sessionID, nextCursor: 3, cols: 120, rows: 40)
            ],
            eventResponses: []
        )
        let remote = RemoteTerminalSession(transport: transport, pollIntervalNanoseconds: 5_000_000)

        try await remote.connect(baseURL: baseURL, cols: 120, rows: 40)
        try await remote.reconnect()

        let createCalls = await transport.createCalls()
        let attachCalls = await transport.attachCalls()

        XCTAssertEqual(createCalls.count, 1)
        XCTAssertEqual(attachCalls.count, 2)
        XCTAssertEqual(attachCalls[1].sessionID, sessionID)
        XCTAssertEqual(remote.telemetry.reconnectCount, 1)
        remote.disconnect()
    }

    @MainActor
    func testRemoteTerminalSessionRestoreResumesWithoutCreate() async throws {
        let baseURL = URL(string: "http://127.0.0.1:8787")!
        let sessionID = "session-remote-restore"
        let transport = MockRemoteTerminalTransport(
            sessionID: sessionID,
            attachResponses: [
                makeAttachResponse(sessionID: sessionID, nextCursor: 9, cols: 130, rows: 44)
            ],
            eventResponses: []
        )
        let remote = RemoteTerminalSession(transport: transport, pollIntervalNanoseconds: 5_000_000)

        try remote.restore(
            baseURL: baseURL,
            sessionID: sessionID,
            terminalID: "main",
            cols: 130,
            rows: 44,
            cursor: 7
        )
        try await remote.resumeIfNeeded()

        let createCalls = await transport.createCalls()
        let attachCalls = await transport.attachCalls()

        XCTAssertEqual(createCalls.count, 0)
        XCTAssertEqual(attachCalls.count, 1)
        XCTAssertEqual(attachCalls[0].sessionID, sessionID)
        XCTAssertEqual(attachCalls[0].resumeCursor, 7)
        XCTAssertEqual(remote.state, .running)
        remote.disconnect()
    }

    @MainActor
    private func waitUntil(
        timeoutSeconds: TimeInterval = 1.5,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let timeout = Date().addingTimeInterval(timeoutSeconds)
        while Date() < timeout {
            if condition() { return }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor MockRemoteTerminalTransport: RemoteTerminalTransport {
    struct CreateCall: Sendable {
        let baseURL: URL
        let workspacePath: String?
    }

    struct AttachCall: Sendable {
        let baseURL: URL
        let sessionID: String
        let cols: Int
        let rows: Int
        let terminalID: String?
        let resumeCursor: UInt64?
    }

    struct InputCall: Sendable {
        let baseURL: URL
        let sessionID: String
        let data: Data
        let source: TerminalInputSource?
    }

    struct ResizeCall: Sendable {
        let baseURL: URL
        let sessionID: String
        let cols: Int
        let rows: Int
        let source: TerminalResizeSource?
    }

    private let summary: SessionSummary
    private var createCallsStore: [CreateCall] = []
    private var attachCallsStore: [AttachCall] = []
    private var inputCallsStore: [InputCall] = []
    private var resizeCallsStore: [ResizeCall] = []
    private var attachResponses: [TerminalAttachResponse]
    private var eventResponses: [Result<TerminalEventsResponse, Error>]

    init(
        sessionID: String,
        attachResponses: [TerminalAttachResponse],
        eventResponses: [Result<TerminalEventsResponse, Error>]
    ) {
        self.summary = SessionSummary(id: sessionID, status: .running)
        self.attachResponses = attachResponses
        self.eventResponses = eventResponses
    }

    func createSession(baseURL: URL, workspacePath: String?) async throws -> CreateSessionResponse {
        createCallsStore.append(CreateCall(baseURL: baseURL, workspacePath: workspacePath))
        return CreateSessionResponse(session: summary)
    }

    func terminalAttach(
        baseURL: URL,
        sessionID: String,
        cols: Int,
        rows: Int,
        terminalID: String?,
        resumeCursor: UInt64?
    ) async throws -> TerminalAttachResponse {
        attachCallsStore.append(
            AttachCall(
                baseURL: baseURL,
                sessionID: sessionID,
                cols: cols,
                rows: rows,
                terminalID: terminalID,
                resumeCursor: resumeCursor
            )
        )

        if !attachResponses.isEmpty {
            return attachResponses.removeFirst()
        }

        return makeAttachResponse(sessionID: summary.id, nextCursor: 0, cols: cols, rows: rows)
    }

    func terminalInputBytes(
        baseURL: URL,
        sessionID: String,
        data: Data,
        source: TerminalInputSource?
    ) async throws -> TerminalInputBytesResponse {
        inputCallsStore.append(
            InputCall(
                baseURL: baseURL,
                sessionID: sessionID,
                data: data,
                source: source
            )
        )
        return TerminalInputBytesResponse(
            accepted: true,
            session: summary,
            terminal: TerminalDescriptor(terminalID: "main", cols: 120, rows: 40, status: .running)
        )
    }

    func terminalResize(
        baseURL: URL,
        sessionID: String,
        cols: Int,
        rows: Int,
        source: TerminalResizeSource?
    ) async throws -> TerminalResizeResponse {
        resizeCallsStore.append(
            ResizeCall(
                baseURL: baseURL,
                sessionID: sessionID,
                cols: cols,
                rows: rows,
                source: source
            )
        )
        return TerminalResizeResponse(
            accepted: true,
            session: summary,
            terminal: TerminalDescriptor(terminalID: "main", cols: cols, rows: rows, status: .running)
        )
    }

    func terminalEvents(
        baseURL: URL,
        sessionID: String,
        cursor: UInt64
    ) async throws -> TerminalEventsResponse {
        if !eventResponses.isEmpty {
            return try eventResponses.removeFirst().get()
        }

        return TerminalEventsResponse(
            sessionID: sessionID,
            terminalID: "main",
            nextCursor: cursor,
            events: []
        )
    }

    func createCalls() -> [CreateCall] {
        createCallsStore
    }

    func attachCalls() -> [AttachCall] {
        attachCallsStore
    }

    func inputCalls() -> [InputCall] {
        inputCallsStore
    }

    func resizeCalls() -> [ResizeCall] {
        resizeCallsStore
    }
}

private func makeAttachResponse(
    sessionID: String,
    nextCursor: UInt64,
    cols: Int,
    rows: Int
) -> TerminalAttachResponse {
    TerminalAttachResponse(
        accepted: true,
        session: SessionSummary(id: sessionID, status: .running),
        terminal: TerminalDescriptor(terminalID: "main", cols: cols, rows: rows, status: .running),
        nextCursor: nextCursor
    )
}
