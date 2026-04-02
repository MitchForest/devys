import XCTest
import ChatCore
@testable import ServerProtocol

final class ServerProtocolTests: XCTestCase {
    func testHealthRoundTrip() throws {
        let input = HealthResponse(serverName: "devys-mac-server", version: "0.1.0")
        let data = try ServerJSONCoding.makeEncoder().encode(input)
        let output = try ServerJSONCoding.makeDecoder().decode(HealthResponse.self, from: data)
        XCTAssertEqual(output.status, "ok")
        XCTAssertEqual(output.serverName, "devys-mac-server")
        XCTAssertEqual(output.version, "0.1.0")
    }

    func testStreamEventRoundTrip() throws {
        let input = StreamEventEnvelope.text(
            seq: 1,
            type: .heartbeat,
            message: "tick",
            sessionID: "session-1"
        )
        let data = try ServerJSONCoding.makeEncoder().encode(input)
        let output = try ServerJSONCoding.makeDecoder().decode(StreamEventEnvelope.self, from: data)
        XCTAssertEqual(output.seq, 1)
        XCTAssertEqual(output.type, .heartbeat)
        XCTAssertEqual(output.message, "tick")
        XCTAssertEqual(output.sessionID, "session-1")
    }

    func testEnvelopeRoundTrip() throws {
        let request = RequestEnvelope(
            requestID: "req-1",
            type: "session.create",
            payload: .object(["workspacePath": .string("/tmp/workspace")])
        )
        let requestData = try ServerJSONCoding.makeEncoder().encode(request)
        let decodedRequest = try ServerJSONCoding.makeDecoder().decode(RequestEnvelope.self, from: requestData)

        XCTAssertEqual(decodedRequest.requestID, "req-1")
        XCTAssertEqual(decodedRequest.type, "session.create")
        XCTAssertEqual(decodedRequest.payload?["workspacePath"]?.stringValue, "/tmp/workspace")

        let response = ResponseEnvelope(
            requestID: "req-1",
            ok: false,
            error: ErrorEnvelope(code: "invalid_request", message: "missing field")
        )
        let responseData = try ServerJSONCoding.makeEncoder().encode(response)
        let decodedResponse = try ServerJSONCoding.makeDecoder().decode(ResponseEnvelope.self, from: responseData)

        XCTAssertEqual(decodedResponse.requestID, "req-1")
        XCTAssertFalse(decodedResponse.ok)
        XCTAssertEqual(decodedResponse.error?.code, "invalid_request")
    }

    func testTerminalPayloadRoundTrip() throws {
        let event = StreamEventEnvelope.terminalOutput(
            seq: 17,
            terminalID: "main",
            stream: .stdout,
            chunkBase64: "aGVsbG8K",
            byteCount: 6,
            sessionID: "session-1"
        )
        let data = try ServerJSONCoding.makeEncoder().encode(event)
        let decoded = try ServerJSONCoding.makeDecoder().decode(StreamEventEnvelope.self, from: data)

        XCTAssertEqual(decoded.type, .terminalOutput)
        XCTAssertEqual(decoded.sessionID, "session-1")
        XCTAssertEqual(decoded.terminalOutputPayload?.chunk, "aGVsbG8K")
    }

    func testTerminalV2EventPayloadRoundTrip() throws {
        let outputEvent = StreamEventEnvelope.terminalOutput(
            seq: 31,
            terminalID: "main",
            stream: .stdout,
            chunkBase64: "aGVsbG8K",
            byteCount: 6,
            sessionID: "session-1"
        )
        let outputData = try ServerJSONCoding.makeEncoder().encode(outputEvent)
        let decodedOutput = try ServerJSONCoding.makeDecoder().decode(StreamEventEnvelope.self, from: outputData)

        XCTAssertEqual(decodedOutput.type, .terminalOutput)
        XCTAssertEqual(decodedOutput.terminalOutputPayload?.terminalID, "main")
        XCTAssertEqual(decodedOutput.terminalOutputPayload?.stream, .stdout)
        XCTAssertEqual(decodedOutput.terminalOutputPayload?.encoding, .base64)
        XCTAssertEqual(decodedOutput.terminalOutputPayload?.chunk, "aGVsbG8K")
        XCTAssertEqual(decodedOutput.terminalOutputPayload?.byteCount, 6)

        let openedEvent = StreamEventEnvelope.terminalOpened(
            seq: 32,
            terminalID: "main",
            cols: 132,
            rows: 42,
            status: .running,
            sessionID: "session-1"
        )
        let openedData = try ServerJSONCoding.makeEncoder().encode(openedEvent)
        let decodedOpened = try ServerJSONCoding.makeDecoder().decode(StreamEventEnvelope.self, from: openedData)

        XCTAssertEqual(decodedOpened.type, .terminalOpened)
        XCTAssertEqual(decodedOpened.terminalOpenedPayload?.terminalID, "main")
        XCTAssertEqual(decodedOpened.terminalOpenedPayload?.cols, 132)
        XCTAssertEqual(decodedOpened.terminalOpenedPayload?.rows, 42)
        XCTAssertEqual(decodedOpened.terminalOpenedPayload?.status, .running)
    }

    func testSessionSummaryRoundTrip() throws {
        let summary = SessionSummary(
            id: "session-1",
            status: .running,
            workspacePath: "/tmp/project"
        )
        let data = try ServerJSONCoding.makeEncoder().encode(summary)
        let decoded = try ServerJSONCoding.makeDecoder().decode(SessionSummary.self, from: data)

        XCTAssertEqual(decoded.id, "session-1")
        XCTAssertEqual(decoded.status, .running)
        XCTAssertEqual(decoded.workspacePath, "/tmp/project")
    }

    func testSessionAPIRoundTrip() throws {
        let create = CreateSessionRequest(workspacePath: "/tmp/project")
        let createData = try ServerJSONCoding.makeEncoder().encode(create)
        let decodedCreate = try ServerJSONCoding.makeDecoder().decode(CreateSessionRequest.self, from: createData)
        XCTAssertEqual(decodedCreate.workspacePath, "/tmp/project")

        let run = RunSessionRequest(
            command: "codex",
            arguments: ["run", "--json"],
            workingDirectory: "/tmp/project",
            environment: ["A": "B"]
        )
        let runData = try ServerJSONCoding.makeEncoder().encode(run)
        let decodedRun = try ServerJSONCoding.makeDecoder().decode(RunSessionRequest.self, from: runData)
        XCTAssertEqual(decodedRun.command, "codex")
        XCTAssertEqual(decodedRun.arguments, ["run", "--json"])
        XCTAssertEqual(decodedRun.workingDirectory, "/tmp/project")
        XCTAssertEqual(decodedRun.environment?["A"], "B")

        let listed = ListSessionsResponse(
            sessions: [
                SessionSummary(id: "session-1", status: .running, workspacePath: "/tmp/project"),
                SessionSummary(id: "session-2", status: .completed, workspacePath: "/tmp/other")
            ]
        )
        let listedData = try ServerJSONCoding.makeEncoder().encode(listed)
        let decodedListed = try ServerJSONCoding.makeDecoder().decode(ListSessionsResponse.self, from: listedData)
        XCTAssertEqual(decodedListed.sessions.map(\.id), ["session-1", "session-2"])
    }

    func testConversationSessionAPIRoundTrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1_706_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_706_000_100)
        let session = Session(
            id: "sess-v1",
            title: "Implement Phase 0",
            harnessType: .codex,
            model: "gpt-5-codex",
            workspaceRoot: "/tmp/project",
            branch: "feature/phase-0",
            status: .idle,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessagePreview: "Ready",
            unreadCount: 0
        )

        let listResponse = SessionListResponse(sessions: [session])
        let listData = try ServerJSONCoding.makeEncoder().encode(listResponse)
        let decodedList = try ServerJSONCoding.makeDecoder().decode(SessionListResponse.self, from: listData)
        XCTAssertEqual(decodedList.sessions, [session])

        let createRequest = SessionCreateRequest(
            title: "Implement Phase 0",
            harnessType: .codex,
            model: "gpt-5-codex",
            workspaceRoot: "/tmp/project",
            branch: "feature/phase-0"
        )
        let createData = try ServerJSONCoding.makeEncoder().encode(createRequest)
        let decodedCreate = try ServerJSONCoding.makeDecoder().decode(
            SessionCreateRequest.self,
            from: createData
        )
        XCTAssertEqual(decodedCreate.title, "Implement Phase 0")
        XCTAssertEqual(decodedCreate.harnessType, .codex)
        XCTAssertEqual(decodedCreate.model, "gpt-5-codex")

        let archiveResponse = SessionArchiveResponse(session: session)
        let archiveData = try ServerJSONCoding.makeEncoder().encode(archiveResponse)
        let decodedArchive = try ServerJSONCoding.makeDecoder().decode(
            SessionArchiveResponse.self,
            from: archiveData
        )
        XCTAssertEqual(decodedArchive.session.id, "sess-v1")
    }

    func testConversationStreamEnvelopeRoundTrip() throws {
        let message = Message(
            id: "msg-v1",
            sessionID: "sess-v1",
            role: .assistant,
            text: "Applying patch now.",
            streamingState: .streaming,
            timestamp: .now
        )
        let payload = try ServerJSONCoding.encodeValue(
            ["message": message]
        )
        let envelope = ConversationEventEnvelope(
            schemaVersion: 1,
            eventID: "evt-v1",
            sessionID: "sess-v1",
            sequence: 7,
            timestamp: .now,
            type: .messageUpsert,
            payload: payload
        )

        let data = try ServerJSONCoding.makeEncoder().encode(envelope)
        let decoded = try ServerJSONCoding.makeDecoder().decode(ConversationEventEnvelope.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.eventID, "evt-v1")
        XCTAssertEqual(decoded.sessionID, "sess-v1")
        XCTAssertEqual(decoded.sequence, 7)
        XCTAssertEqual(decoded.type, .messageUpsert)

        let decodedPayload = decoded.decodePayload([String: Message].self)
        XCTAssertEqual(decodedPayload?["message"]?.id, "msg-v1")
    }

    func testConversationMessageAPIRoundTrip() throws {
        let messageRequest = ConversationUserMessageRequest(
            text: "Ship it",
            clientMessageID: "client-msg-1"
        )
        let requestData = try ServerJSONCoding.makeEncoder().encode(messageRequest)
        let decodedRequest = try ServerJSONCoding.makeDecoder().decode(
            ConversationUserMessageRequest.self,
            from: requestData
        )
        XCTAssertEqual(decodedRequest.text, "Ship it")
        XCTAssertEqual(decodedRequest.clientMessageID, "client-msg-1")

        let approval = ConversationApprovalResponseRequest(
            requestID: "approval-1",
            decision: .approve,
            note: "Looks safe"
        )
        let approvalData = try ServerJSONCoding.makeEncoder().encode(approval)
        let decodedApproval = try ServerJSONCoding.makeDecoder().decode(
            ConversationApprovalResponseRequest.self,
            from: approvalData
        )
        XCTAssertEqual(decodedApproval.requestID, "approval-1")
        XCTAssertEqual(decodedApproval.decision, .approve)
        XCTAssertEqual(decodedApproval.note, "Looks safe")

        let userInput = ConversationUserInputResponseRequest(requestID: "input-1", value: "run tests")
        let userInputData = try ServerJSONCoding.makeEncoder().encode(userInput)
        let decodedUserInput = try ServerJSONCoding.makeDecoder().decode(
            ConversationUserInputResponseRequest.self,
            from: userInputData
        )
        XCTAssertEqual(decodedUserInput.requestID, "input-1")
        XCTAssertEqual(decodedUserInput.value, "run tests")

        let actionResponse = ConversationActionResponse(accepted: true)
        let actionData = try ServerJSONCoding.makeEncoder().encode(actionResponse)
        let decodedAction = try ServerJSONCoding.makeDecoder().decode(ConversationActionResponse.self, from: actionData)
        XCTAssertTrue(decodedAction.accepted)
    }

    func testCapabilitiesRoundTrip() throws {
        let input = ServerCapabilitiesResponse(
            tmuxAvailable: true,
            claudeAvailable: false,
            codexAvailable: true
        )
        let data = try ServerJSONCoding.makeEncoder().encode(input)
        let output = try ServerJSONCoding.makeDecoder().decode(ServerCapabilitiesResponse.self, from: data)
        XCTAssertTrue(output.tmuxAvailable)
        XCTAssertFalse(output.claudeAvailable)
        XCTAssertTrue(output.codexAvailable)
    }

    func testTerminalAPIRoundTrip() throws {
        let descriptor = TerminalDescriptor(terminalID: "main", cols: 120, rows: 40, status: .running)

        let attachRequest = TerminalAttachRequest(
            cols: 120,
            rows: 40,
            terminalID: "main",
            resumeCursor: 99
        )
        let attachRequestData = try ServerJSONCoding.makeEncoder().encode(attachRequest)
        let decodedAttachRequest = try ServerJSONCoding.makeDecoder().decode(
            TerminalAttachRequest.self,
            from: attachRequestData
        )
        XCTAssertEqual(decodedAttachRequest.cols, 120)
        XCTAssertEqual(decodedAttachRequest.rows, 40)
        XCTAssertEqual(decodedAttachRequest.terminalID, "main")
        XCTAssertEqual(decodedAttachRequest.resumeCursor, 99)

        let summary = SessionSummary(id: "session-1", status: .running, workspacePath: "/tmp/project")
        let attachResponse = TerminalAttachResponse(
            accepted: true,
            session: summary,
            terminal: descriptor,
            nextCursor: 101
        )
        let attachResponseData = try ServerJSONCoding.makeEncoder().encode(attachResponse)
        let decodedAttachResponse = try ServerJSONCoding.makeDecoder().decode(
            TerminalAttachResponse.self,
            from: attachResponseData
        )
        XCTAssertTrue(decodedAttachResponse.accepted)
        XCTAssertEqual(decodedAttachResponse.terminal.terminalID, "main")
        XCTAssertEqual(decodedAttachResponse.nextCursor, 101)

        let inputRequest = TerminalInputBytesRequest(bytesBase64: "AQID", source: .programmatic)
        let inputRequestData = try ServerJSONCoding.makeEncoder().encode(inputRequest)
        let decodedInputRequest = try ServerJSONCoding.makeDecoder().decode(
            TerminalInputBytesRequest.self,
            from: inputRequestData
        )
        XCTAssertEqual(decodedInputRequest.bytesBase64, "AQID")
        XCTAssertEqual(decodedInputRequest.source, .programmatic)

        let resizeRequest = TerminalResizeRequest(cols: 100, rows: 30, source: .rotation)
        let resizeRequestData = try ServerJSONCoding.makeEncoder().encode(resizeRequest)
        let decodedResizeRequest = try ServerJSONCoding.makeDecoder().decode(
            TerminalResizeRequest.self,
            from: resizeRequestData
        )
        XCTAssertEqual(decodedResizeRequest.cols, 100)
        XCTAssertEqual(decodedResizeRequest.rows, 30)
        XCTAssertEqual(decodedResizeRequest.source, .rotation)

        let eventsResponse = TerminalEventsResponse(
            sessionID: "session-1",
            terminalID: "main",
            nextCursor: 17,
            events: [
                .terminalOpened(
                    seq: 16,
                    terminalID: "main",
                    cols: 120,
                    rows: 40,
                    status: .running,
                    sessionID: "session-1"
                ),
                .terminalOutput(
                    seq: 17,
                    terminalID: "main",
                    stream: .stdout,
                    chunkBase64: "aGVsbG8K",
                    byteCount: 6,
                    sessionID: "session-1"
                )
            ]
        )
        let eventsData = try ServerJSONCoding.makeEncoder().encode(eventsResponse)
        let decodedEvents = try ServerJSONCoding.makeDecoder().decode(TerminalEventsResponse.self, from: eventsData)
        XCTAssertEqual(decodedEvents.sessionID, "session-1")
        XCTAssertEqual(decodedEvents.terminalID, "main")
        XCTAssertEqual(decodedEvents.nextCursor, 17)
        XCTAssertEqual(decodedEvents.events.count, 2)
    }

    func testPairingAPIRoundTrip() throws {
        let challenge = PairingChallengeResponse(
            challengeID: "challenge-1",
            setupCode: "123456",
            expiresAt: .now.addingTimeInterval(600),
            serverName: "devys-mac-server",
            serverFingerprint: "fingerprint-1",
            canonicalHostname: "devys-mac",
            fallbackAddress: "100.64.0.1"
        )
        let challengeData = try ServerJSONCoding.makeEncoder().encode(challenge)
        let decodedChallenge = try ServerJSONCoding.makeDecoder().decode(
            PairingChallengeResponse.self,
            from: challengeData
        )
        XCTAssertEqual(decodedChallenge.challengeID, "challenge-1")
        XCTAssertEqual(decodedChallenge.setupCode, "123456")
        XCTAssertEqual(decodedChallenge.serverFingerprint, "fingerprint-1")

        let exchangeRequest = PairingExchangeRequest(
            challengeID: "challenge-1",
            setupCode: "123456",
            deviceName: "iPhone"
        )
        let exchangeRequestData = try ServerJSONCoding.makeEncoder().encode(exchangeRequest)
        let decodedExchangeRequest = try ServerJSONCoding.makeDecoder().decode(
            PairingExchangeRequest.self,
            from: exchangeRequestData
        )
        XCTAssertEqual(decodedExchangeRequest.challengeID, "challenge-1")
        XCTAssertEqual(decodedExchangeRequest.deviceName, "iPhone")

        let pairingRecord = PairingRecord(
            id: "pairing-1",
            deviceName: "iPhone",
            createdAt: .now,
            updatedAt: .now,
            status: .active
        )
        let exchangeResponse = PairingExchangeResponse(pairing: pairingRecord, authToken: "token-1")
        let exchangeResponseData = try ServerJSONCoding.makeEncoder().encode(exchangeResponse)
        let decodedExchangeResponse = try ServerJSONCoding.makeDecoder().decode(
            PairingExchangeResponse.self,
            from: exchangeResponseData
        )
        XCTAssertEqual(decodedExchangeResponse.pairing.id, "pairing-1")
        XCTAssertEqual(decodedExchangeResponse.authToken, "token-1")
    }

    func testCommandProfileAPIRoundTrip() throws {
        let profile = CommandProfile(
            id: "cc",
            label: "Claude Code",
            command: "claude",
            arguments: ["code"],
            environment: ["A": "B"],
            requiredCapabilities: [.tmux, .claude],
            isDefault: true
        )

        let saveRequest = SaveCommandProfileRequest(profile: profile)
        let saveRequestData = try ServerJSONCoding.makeEncoder().encode(saveRequest)
        let decodedSaveRequest = try ServerJSONCoding.makeDecoder().decode(
            SaveCommandProfileRequest.self,
            from: saveRequestData
        )
        XCTAssertEqual(decodedSaveRequest.profile.id, "cc")

        let listResponse = ListCommandProfilesResponse(profiles: [profile])
        let listData = try ServerJSONCoding.makeEncoder().encode(listResponse)
        let decodedList = try ServerJSONCoding.makeDecoder().decode(ListCommandProfilesResponse.self, from: listData)
        XCTAssertEqual(decodedList.profiles.count, 1)
        XCTAssertEqual(decodedList.profiles.first?.requiredCapabilities, [.tmux, .claude])

        let validateResponse = ValidateCommandProfileResponse(
            isValid: false,
            errors: ["Command is required"],
            warnings: ["No environment overrides set"]
        )
        let validateData = try ServerJSONCoding.makeEncoder().encode(validateResponse)
        let decodedValidate = try ServerJSONCoding.makeDecoder().decode(
            ValidateCommandProfileResponse.self,
            from: validateData
        )
        XCTAssertFalse(decodedValidate.isValid)
        XCTAssertEqual(decodedValidate.errors, ["Command is required"])
    }
}
