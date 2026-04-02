import Foundation
import Network
import ServerProtocol

extension HTTPServer {
    func decodeTerminalAttachRequest(_ request: HTTPRequest, on connection: NWConnection) -> TerminalAttachRequest? {
        do {
            return try ServerJSONCoding.makeDecoder().decode(TerminalAttachRequest.self, from: request.body)
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode terminal attach payload",
                on: connection
            )
            return nil
        }
    }

    func validatedTerminalDimensions(
        cols: Int,
        rows: Int,
        sessionID: String,
        on connection: NWConnection
    ) -> (cols: Int, rows: Int)? {
        guard let dimensions = HTTPServerUtilities.normalizedTerminalDimensions(cols: cols, rows: rows) else {
            sendError(
                statusCode: 400,
                code: "terminal_resize_invalid_dimensions",
                message: "Terminal dimensions must be greater than zero",
                details: [
                    "sessionId": .string(sessionID),
                    "cols": .int(cols),
                    "rows": .int(rows)
                ],
                on: connection
            )
            return nil
        }
        return dimensions
    }

    func ensureTmuxAvailableForAttach(sessionID: String, on connection: NWConnection) -> Bool {
        guard tmuxManager.isAvailable else {
            sendError(
                statusCode: 503,
                code: "terminal_attach_failed",
                message: "tmux is required for interactive terminal attach",
                details: ["sessionId": .string(sessionID)],
                on: connection
            )
            return false
        }
        return true
    }

    func normalizedTerminalID(from rawTerminalID: String?) -> String {
        rawTerminalID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "main"
    }

    func prepareTmuxAttach(
        session: RunSession,
        sessionID: String,
        terminalID: String,
        tmuxSessionName: String,
        dimensions: (cols: Int, rows: Int),
        on connection: NWConnection
    ) -> Bool {
        do {
            try tmuxManager.createSession(name: tmuxSessionName, workingDirectory: session.workspacePath)
            try tmuxManager.resizeWindow(sessionName: tmuxSessionName, cols: dimensions.cols, rows: dimensions.rows)
            return true
        } catch TmuxManagerError.commandFailed(let message) {
            sendTerminalAttachFailed(
                sessionID: sessionID,
                terminalID: terminalID,
                message: message,
                on: connection
            )
            return false
        } catch {
            sendTerminalAttachFailed(
                sessionID: sessionID,
                terminalID: terminalID,
                message: error.localizedDescription,
                on: connection
            )
            return false
        }
    }

    func startTerminalAttachStream(
        session: RunSession,
        sessionID: String,
        terminalID: String,
        on connection: NWConnection
    ) -> Bool {
        do {
            try startTmuxOutputStream(for: session)
            return true
        } catch {
            session.usingTmux = false
            session.markDirty()
            sendTerminalAttachFailed(
                sessionID: sessionID,
                terminalID: terminalID,
                message: "Failed to start terminal output stream: \(error.localizedDescription)",
                on: connection
            )
            return false
        }
    }

    func finalizeTerminalAttach(
        session: RunSession,
        terminalID: String,
        dimensions: (cols: Int, rows: Int),
        attachRequest: TerminalAttachRequest
    ) {
        session.tmuxSessionName = session.tmuxSessionName ?? HTTPServerUtilities.tmuxSessionName(for: session.id)
        session.usingTmux = true
        session.setTerminalID(terminalID)
        session.setTerminalDimensions(cols: dimensions.cols, rows: dimensions.rows)
        session.markStatus(.running)
        session.appendTerminalStatus(.running)
        if (attachRequest.resumeCursor ?? 0) == 0 {
            session.appendTerminalOpened()
        }
        session.markDirty()
    }

    func sendTerminalAttachAccepted(session: RunSession, on connection: NWConnection) {
        let nextCursor = session.events.last?.seq ?? 0
        sendJSON(
            statusCode: 200,
            payload: TerminalAttachResponse(
                accepted: true,
                session: session.summary,
                terminal: session.terminalDescriptor,
                nextCursor: nextCursor
            ),
            on: connection
        )
    }

    func sendTerminalAttachFailed(
        sessionID: String,
        terminalID: String,
        message: String,
        on connection: NWConnection
    ) {
        sendError(
            statusCode: 500,
            code: "terminal_attach_failed",
            message: message,
            details: [
                "sessionId": .string(sessionID),
                "terminalId": .string(terminalID)
            ],
            on: connection
        )
    }

    func decodeTerminalInputRequest(_ request: HTTPRequest, on connection: NWConnection) -> TerminalInputBytesRequest? {
        do {
            return try ServerJSONCoding.makeDecoder().decode(TerminalInputBytesRequest.self, from: request.body)
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode terminal input payload",
                on: connection
            )
            return nil
        }
    }

    func validatedAttachedTmuxSession(
        session: RunSession,
        sessionID: String,
        on connection: NWConnection
    ) -> String? {
        guard session.usingTmux, let tmuxSessionName = session.tmuxSessionName else {
            sendError(
                statusCode: 409,
                code: "terminal_not_attached",
                message: "Session is not attached to an interactive terminal",
                details: ["sessionId": .string(sessionID)],
                on: connection
            )
            return nil
        }
        return tmuxSessionName
    }

    func decodeTerminalInputPayload(
        _ request: TerminalInputBytesRequest,
        sessionID: String,
        on connection: NWConnection
    ) -> Data? {
        guard let payloadData = Data(base64Encoded: request.bytesBase64) else {
            sendError(
                statusCode: 400,
                code: "terminal_input_invalid_base64",
                message: "bytesBase64 must be valid base64",
                details: ["sessionId": .string(sessionID)],
                on: connection
            )
            return nil
        }
        return payloadData
    }

    func sendTerminalInputAccepted(session: RunSession, on connection: NWConnection) {
        sendJSON(
            statusCode: 200,
            payload: TerminalInputBytesResponse(
                accepted: true,
                session: session.summary,
                terminal: session.terminalDescriptor
            ),
            on: connection
        )
    }

    func decodeTerminalResizeRequest(_ request: HTTPRequest, on connection: NWConnection) -> TerminalResizeRequest? {
        do {
            return try ServerJSONCoding.makeDecoder().decode(TerminalResizeRequest.self, from: request.body)
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode terminal resize payload",
                on: connection
            )
            return nil
        }
    }

    func sendTerminalResizeAccepted(session: RunSession, on connection: NWConnection) {
        sendJSON(
            statusCode: 200,
            payload: TerminalResizeResponse(
                accepted: true,
                session: session.summary,
                terminal: session.terminalDescriptor
            ),
            on: connection
        )
    }

    func validatedTerminalEventsCursor(
        request: HTTPRequest,
        sessionID: String,
        on connection: NWConnection
    ) -> UInt64? {
        guard
            let rawCursor = request.query["cursor"],
            !rawCursor.isEmpty,
            let cursor = UInt64(rawCursor)
        else {
            sendError(
                statusCode: 400,
                code: "terminal_events_invalid_cursor",
                message: "Cursor query parameter is required and must be an unsigned integer",
                details: [
                    "sessionId": .string(sessionID),
                    "cursor": .string(request.query["cursor"] ?? "")
                ],
                on: connection
            )
            return nil
        }
        return cursor
    }

    func bindTmuxControlSession(_ controlSession: TmuxControlSession, to session: RunSession) {
        let controlProcess = controlSession.process
        let sessionID = session.id
        session.tmuxOutputSession = controlSession
        session.tmuxOutputBuffer.removeAll(keepingCapacity: false)
        session.markDirty()

        installTmuxStdoutHandler(sessionID: sessionID, controlProcess: controlProcess, controlSession: controlSession)
        installTmuxStderrHandler(sessionID: sessionID, controlProcess: controlProcess, controlSession: controlSession)
        installTmuxTerminationHandler(
            sessionID: sessionID,
            controlSession: controlSession
        )
    }

    func installTmuxStdoutHandler(
        sessionID: String,
        controlProcess: Process,
        controlSession: TmuxControlSession
    ) {
        controlSession.stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                guard
                    let self,
                    let current = self.runSessions[sessionID],
                    current.tmuxOutputSession?.process === controlProcess
                else {
                    return
                }
                current.tmuxOutputBuffer.append(data)
                self.drainTmuxControlBuffer(for: current)
            }
        }
    }

    func installTmuxStderrHandler(
        sessionID: String,
        controlProcess: Process,
        controlSession: TmuxControlSession
    ) {
        controlSession.stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                guard
                    let self,
                    let current = self.runSessions[sessionID],
                    current.tmuxOutputSession?.process === controlProcess
                else {
                    return
                }
                let message = (String(data: data, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { return }
                current.appendText(type: .error, message: "tmux-control-stderr \(message)")
            }
        }
    }

    func installTmuxTerminationHandler(
        sessionID: String,
        controlSession: TmuxControlSession
    ) {
        controlSession.process.terminationHandler = { [weak self] process in
            self?.queue.async { [weak self] in
                guard
                    let self,
                    let current = self.runSessions[sessionID],
                    current.tmuxOutputSession?.process === process
                else {
                    return
                }
                self.stopTmuxOutputStream(for: current, terminateProcess: false)
                if current.status == .running || current.status == .stopping || current.awaitingExitMarker {
                    current.appendText(
                        type: .error,
                        message: "tmux-control-disconnected status=\(process.terminationStatus)"
                    )
                }
            }
        }
    }
}
