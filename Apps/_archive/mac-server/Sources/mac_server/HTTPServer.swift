import Foundation
import Network
import ServerProtocol

func writeServerLog(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

struct ConversationStreamRegistration {
    let sessionID: String
    let subscriberID: UUID
    let heartbeatTask: Task<Void, Never>
}

final class HTTPServer: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "com.devys.mac-server.listener")
    let serverName: String
    let version: String
    let serverFingerprint: String
    let sessionStore: SessionStore
    let pairingStore: PairingStore
    let commandProfileStore: CommandProfileStore
    var streamSessions: [ObjectIdentifier: StreamSession] = [:]
    var nextStreamEventID: UInt64 = 1
    var runSessions: [String: RunSession] = [:]
    var pairings: [String: PairingRecord] = [:]
    var pairingTokens: [String: String] = [:]
    var pairingChallenges: [String: PairingChallenge] = [:]
    var commandProfiles: [String: CommandProfile] = [:]
    let conversationStreamLock = NSLock()
    var conversationStreams: [ObjectIdentifier: ConversationStreamRegistration] = [:]
    let tmuxManager = TmuxManager()
    let conversationRuntime = ConversationRuntime()

    init(host: String, port: UInt16, serverName: String, version: String) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HTTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: nwPort)
        self.serverName = serverName
        self.version = version
        self.sessionStore = try SessionStore()
        self.pairingStore = try PairingStore()
        self.commandProfileStore = try CommandProfileStore()
        self.serverFingerprint = try ServerIdentityStore().loadOrCreateFingerprint()

        let nwHost = NWEndpoint.Host(host)
        listener.service = nil
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                writeServerLog("mac-server listening on \(nwHost):\(port)")
            case .failed(let error):
                writeServerLog("listener failed: \(error)")
            default:
                break
            }
        }

        loadPersistedRunSessions()
        loadPersistedPairings()
        loadPersistedCommandProfiles()

        Task {
            await conversationRuntime.loadPersistedSessions()
        }
    }

    func start() {
        listener.start(queue: queue)
    }

    func runForever() {
        dispatchMain()
    }
}

extension HTTPServer {
    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                self.endStream(for: connection)
                self.endConversationStream(for: connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }

            if error != nil {
                self.endStream(for: connection)
                self.endConversationStream(for: connection)
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            switch HTTPServerUtilities.parseRequest(from: nextBuffer) {
            case .request(let request):
                self.handleRequest(request, on: connection)
                return
            case .invalid:
                self.sendStatus(400, body: "Bad Request", on: connection)
                return
            case .needMoreData:
                break
            }

            if nextBuffer.count > 1_000_000 {
                connection.cancel()
                return
            }

            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func handleRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch request.method {
        case "GET":
            handleGET(request, on: connection)
        case "POST":
            handlePOST(request, on: connection)
        case "DELETE":
            handleDELETE(request, on: connection)
        default:
            sendStatus(405, body: "Method Not Allowed", on: connection)
        }
    }

    private func handleGET(_ request: HTTPRequest, on connection: NWConnection) {
        switch request.path {
        case "/health":
            sendHealth(on: connection)
        case "/capabilities":
            sendCapabilities(on: connection)
        case "/stream":
            startStream(on: connection)
        case "/sessions":
            handleListSessions(on: connection)
        case "/pairings":
            handleListPairings(on: connection)
        case "/profiles":
            handleListCommandProfiles(on: connection)
        default:
            let components = request.pathComponents
            // Terminal events: /sessions/{id}/terminal/events
            if
                components.count == 4,
                components[0] == "sessions",
                components[2] == "terminal",
                components[3] == "events"
            {
                handleTerminalEvents(sessionID: components[1], request: request, on: connection)
                return
            }
            // Conversation routes: /v1/conversations/sessions[/...]
            if components.count >= 3,
               components[0] == "v1",
               components[1] == "conversations",
               components[2] == "sessions"
            {
                guard authorizeConversationRequest(request, on: connection) else {
                    return
                }
                if components.count == 3 {
                    handleConversationSessionsList(request: request, on: connection)
                    return
                }
                if components.count >= 4 {
                    let sessionID = components[3]
                    if components.count == 5, components[4] == "resume" {
                        handleConversationSessionResume(sessionID: sessionID, on: connection)
                        return
                    }
                    if components.count == 5, components[4] == "stream" {
                        handleConversationSessionStream(sessionID: sessionID, request: request, on: connection)
                        return
                    }
                }
            }
            sendStatus(404, body: "Not Found", on: connection)
        }
    }

    private func handlePOST(_ request: HTTPRequest, on connection: NWConnection) {
        let components = request.pathComponents

        if handleConversationPOST(components: components, request: request, on: connection) {
            return
        }

        if handlePairingAndProfilesPOST(components: components, request: request, on: connection) {
            return
        }

        if components == ["sessions"] {
            handleCreateSession(request: request, on: connection)
            return
        }

        guard components.count >= 3, components[0] == "sessions" else {
            sendStatus(404, body: "Not Found", on: connection)
            return
        }

        let sessionID = components[1]
        if handleTerminalPOST(
            components: components,
            sessionID: sessionID,
            request: request,
            on: connection
        ) {
            return
        }

        guard components.count == 3 else {
            sendStatus(404, body: "Not Found", on: connection)
            return
        }

        handleSessionControlPOST(action: components[2], sessionID: sessionID, request: request, on: connection)
    }

    private func handleConversationPOST(
        components: [String],
        request: HTTPRequest,
        on connection: NWConnection
    ) -> Bool {
        guard components.count >= 3,
              components[0] == "v1",
              components[1] == "conversations",
              components[2] == "sessions"
        else {
            return false
        }

        guard authorizeConversationRequest(request, on: connection) else {
            return true
        }

        if components.count == 3 {
            handleConversationSessionCreate(request: request, on: connection)
            return true
        }

        guard components.count == 5 else {
            return false
        }

        let sessionID = components[3]
        switch components[4] {
        case "messages":
            handleConversationMessage(sessionID: sessionID, request: request, on: connection)
        case "approval":
            handleConversationApproval(sessionID: sessionID, request: request, on: connection)
        case "input":
            handleConversationUserInput(sessionID: sessionID, request: request, on: connection)
        case "archive":
            handleConversationSessionArchive(sessionID: sessionID, request: request, on: connection)
        case "rename":
            handleConversationSessionRename(sessionID: sessionID, request: request, on: connection)
        default:
            sendStatus(404, body: "Not Found", on: connection)
        }
        return true
    }

    private func handleTerminalPOST(
        components: [String],
        sessionID: String,
        request: HTTPRequest,
        on connection: NWConnection
    ) -> Bool {
        guard components.count == 4, components[2] == "terminal" else {
            return false
        }

        switch components[3] {
        case "attach":
            handleTerminalAttach(sessionID: sessionID, request: request, on: connection)
        case "input":
            handleTerminalInput(sessionID: sessionID, request: request, on: connection)
        case "resize":
            handleTerminalResize(sessionID: sessionID, request: request, on: connection)
        default:
            sendStatus(404, body: "Not Found", on: connection)
        }
        return true
    }

    private func handleSessionControlPOST(
        action: String,
        sessionID: String,
        request: HTTPRequest,
        on connection: NWConnection
    ) {
        switch action {
        case "run":
            handleRunSession(sessionID: sessionID, request: request, on: connection)
        case "stop":
            handleStopSession(sessionID: sessionID, on: connection)
        default:
            sendStatus(404, body: "Not Found", on: connection)
        }
    }

    private func handleDELETE(_ request: HTTPRequest, on connection: NWConnection) {
        let components = request.pathComponents
        // DELETE /v1/conversations/sessions/{id}
        if components.count == 4,
           components[0] == "v1",
           components[1] == "conversations",
           components[2] == "sessions"
        {
            guard authorizeConversationRequest(request, on: connection) else {
                return
            }
            handleConversationSessionDelete(sessionID: components[3], on: connection)
            return
        }
        sendStatus(404, body: "Not Found", on: connection)
    }

    private func handlePairingAndProfilesPOST(
        components: [String],
        request: HTTPRequest,
        on connection: NWConnection
    ) -> Bool {
        switch components {
        case ["pairing", "challenge"]:
            handleCreatePairingChallenge(request: request, on: connection)
            return true
        case ["pairing", "exchange"]:
            handlePairingExchange(request: request, on: connection)
            return true
        case ["profiles"]:
            handleSaveCommandProfile(request: request, on: connection)
            return true
        case ["profiles", "validate"]:
            handleValidateCommandProfile(request: request, on: connection)
            return true
        case ["profiles", "delete"]:
            handleDeleteCommandProfile(request: request, on: connection)
            return true
        default:
            break
        }

        if components.count == 3, components[0] == "pairings" {
            let pairingID = components[1]
            switch components[2] {
            case "rotate":
                handleRotatePairing(pairingID: pairingID, on: connection)
            case "revoke":
                handleRevokePairing(pairingID: pairingID, on: connection)
            default:
                sendStatus(404, body: "Not Found", on: connection)
            }
            return true
        }

        return false
    }

    private func handleCreateSession(request: HTTPRequest, on connection: NWConnection) {
        let createRequest: CreateSessionRequest
        if request.body.isEmpty {
            createRequest = CreateSessionRequest()
        } else {
            do {
                createRequest = try ServerJSONCoding.makeDecoder().decode(CreateSessionRequest.self, from: request.body)
            } catch {
                sendError(
                    statusCode: 400,
                    code: "invalid_request",
                    message: "Unable to decode create session payload",
                    on: connection
                )
                return
            }
        }

        let sessionID = UUID().uuidString
        let session = RunSession(id: sessionID, workspacePath: createRequest.workspacePath)
        configureSessionPersistence(for: session)
        session.appendText(type: .info, message: "session-created")
        runSessions[sessionID] = session

        sendJSON(statusCode: 201, payload: CreateSessionResponse(session: session.summary), on: connection)
    }

    private func handleRunSession(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        guard let session = runSessions[sessionID] else {
            sendError(statusCode: 404, code: "session_not_found", message: "Session not found", on: connection)
            return
        }
        guard let runRequest = decodeRunSessionRequest(request, on: connection) else { return }

        let command = runRequest.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            sendError(statusCode: 400, code: "invalid_command", message: "Command must not be empty", on: connection)
            return
        }

        if session.awaitingExitMarker, session.status == .running {
            sendError(statusCode: 409, code: "session_running", message: "Session is already running", on: connection)
            return
        }

        guard tmuxManager.isAvailable else {
            sendError(
                statusCode: 503,
                code: "tmux_unavailable",
                message: "tmux is required on this server",
                on: connection
            )
            return
        }

        do {
            try runSessionWithTmux(session: session, runRequest: runRequest)
            sendJSON(
                statusCode: 202,
                payload: RunSessionResponse(accepted: true, session: session.summary),
                on: connection
            )
        } catch TmuxManagerError.tmuxNotInstalled {
            sendTmuxUnavailableError(on: connection)
        } catch TmuxManagerError.commandFailed(let message) {
            markSessionRunFailure(session, message: "tmux-error \(message)")
            sendError(statusCode: 500, code: "tmux_command_failed", message: message, on: connection)
        } catch {
            markSessionRunFailure(session, message: "tmux-start-failed \(error.localizedDescription)")
            sendError(statusCode: 500, code: "tmux_start_failed", message: error.localizedDescription, on: connection)
        }
    }

    private func runSessionWithTmux(session: RunSession, runRequest: RunSessionRequest) throws {
        let command = runRequest.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = session.tmuxSessionName ?? HTTPServerUtilities.tmuxSessionName(for: session.id)
        let workingDirectory = runRequest.workingDirectory ?? session.workspacePath

        try tmuxManager.createSession(name: sessionName, workingDirectory: workingDirectory)
        try tmuxManager.resizeWindow(
            sessionName: sessionName,
            cols: session.terminalCols,
            rows: session.terminalRows
        )
        session.tmuxSessionName = sessionName
        session.usingTmux = true
        session.markDirty()

        try startTmuxOutputStream(for: session)

        // Prefix exported env vars for this command line when provided.
        let environmentPrefix: String
        if let env = runRequest.environment, !env.isEmpty {
            let sorted = env.keys.sorted()
            environmentPrefix = sorted
                .map { key in
                    let escapedValue = HTTPServerUtilities.shellEscape(env[key] ?? "")
                    return "export \(key)=\(escapedValue)"
                }
                .joined(separator: "; ") + "; "
        } else {
            environmentPrefix = ""
        }

        let commandLine = ([command] + runRequest.arguments)
            .map(HTTPServerUtilities.shellEscape)
            .joined(separator: " ")
        let wrapped = "\(environmentPrefix)\(commandLine); printf '\\n__DEVYS_EXIT__%s__\\n' \"$?\""

        session.awaitingExitMarker = true
        session.tmuxExitMarkerCarry = Data()
        session.markDirty()
        session.markStatus(.running)
        session.appendTerminalStatus(.starting)
        session.appendText(type: .info, message: "run-requested command=\(command)")
        try tmuxManager.sendKeys(sessionName: sessionName, text: wrapped, pressEnter: true)
        session.appendTerminalStatus(.running)
    }

    private func handleStopSession(sessionID: String, on connection: NWConnection) {
        guard let session = runSessions[sessionID] else {
            sendError(statusCode: 404, code: "session_not_found", message: "Session not found", on: connection)
            return
        }

        if session.usingTmux, let tmuxSessionName = session.tmuxSessionName {
            do {
                try tmuxManager.sendInterrupt(sessionName: tmuxSessionName)
                session.markStatus(.stopping)
                session.awaitingExitMarker = false
                session.markDirty()
                session.appendText(type: .info, message: "stop-requested")
                session.appendTerminalExit(exitCode: 130)
                session.appendTerminalStatus(.exited)
                session.appendTerminalClosed(exitCode: 130, reason: "stopped")
                session.markStatus(.stopped)
            } catch {
                sendError(
                    statusCode: 500,
                    code: "tmux_stop_failed",
                    message: "Failed to stop tmux session: \(error.localizedDescription)",
                    on: connection
                )
                return
            }
        } else {
            session.appendText(type: .info, message: "stop-requested-noop")
        }

        sendJSON(statusCode: 200, payload: StopSessionResponse(session: session.summary), on: connection)
    }

}
