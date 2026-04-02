import Foundation
import Network
import ServerProtocol

extension HTTPServer {
    func handleTerminalAttach(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        guard let session = runSessions[sessionID] else {
            sendError(statusCode: 404, code: "session_not_found", message: "Session not found", on: connection)
            return
        }
        guard let attachRequest = decodeTerminalAttachRequest(request, on: connection) else { return }
        guard let dimensions = validatedTerminalDimensions(
            cols: attachRequest.cols,
            rows: attachRequest.rows,
            sessionID: sessionID,
            on: connection
        ) else {
            return
        }
        guard ensureTmuxAvailableForAttach(sessionID: sessionID, on: connection) else { return }

        let terminalID = normalizedTerminalID(from: attachRequest.terminalID)
        let tmuxSessionName = session.tmuxSessionName ?? HTTPServerUtilities.tmuxSessionName(for: session.id)
        guard prepareTmuxAttach(
            session: session,
            sessionID: sessionID,
            terminalID: terminalID,
            tmuxSessionName: tmuxSessionName,
            dimensions: dimensions,
            on: connection
        ) else {
            return
        }
        guard startTerminalAttachStream(
            session: session,
            sessionID: sessionID,
            terminalID: terminalID,
            on: connection
        ) else {
            return
        }

        finalizeTerminalAttach(
            session: session,
            terminalID: terminalID,
            dimensions: dimensions,
            attachRequest: attachRequest
        )
        sendTerminalAttachAccepted(session: session, on: connection)
    }

    func handleTerminalInput(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        guard let session = runSessions[sessionID] else {
            sendError(statusCode: 404, code: "session_not_found", message: "Session not found", on: connection)
            return
        }
        guard let inputRequest = decodeTerminalInputRequest(request, on: connection) else { return }
        guard let tmuxSessionName = validatedAttachedTmuxSession(
            session: session,
            sessionID: sessionID,
            on: connection
        ) else {
            return
        }
        guard let payloadData = decodeTerminalInputPayload(
            inputRequest,
            sessionID: sessionID,
            on: connection
        ) else {
            return
        }

        if payloadData.isEmpty {
            sendTerminalInputAccepted(session: session, on: connection)
            return
        }

        guard let text = String(data: payloadData, encoding: .utf8) else {
            sendError(
                statusCode: 422,
                code: "terminal_input_not_supported",
                message: "Input bytes must be UTF-8 compatible for tmux send-keys",
                details: ["sessionId": .string(sessionID)],
                on: connection
            )
            return
        }

        do {
            try tmuxManager.sendKeys(sessionName: tmuxSessionName, text: text, pressEnter: false)
            sendTerminalInputAccepted(session: session, on: connection)
        } catch {
            sendError(
                statusCode: 500,
                code: "terminal_input_not_supported",
                message: "Failed to send terminal input: \(error.localizedDescription)",
                details: ["sessionId": .string(sessionID)],
                on: connection
            )
        }
    }

    func handleTerminalResize(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        guard let session = runSessions[sessionID] else {
            sendError(statusCode: 404, code: "session_not_found", message: "Session not found", on: connection)
            return
        }
        guard let resizeRequest = decodeTerminalResizeRequest(request, on: connection) else { return }
        guard let dimensions = validatedTerminalDimensions(
            cols: resizeRequest.cols,
            rows: resizeRequest.rows,
            sessionID: sessionID,
            on: connection
        ) else {
            return
        }
        guard let tmuxSessionName = validatedAttachedTmuxSession(
            session: session,
            sessionID: sessionID,
            on: connection
        ) else {
            return
        }

        do {
            try tmuxManager.resizeWindow(sessionName: tmuxSessionName, cols: dimensions.cols, rows: dimensions.rows)
            session.setTerminalDimensions(cols: dimensions.cols, rows: dimensions.rows)
            session.appendTerminalResized(source: resizeRequest.source)
            session.markDirty()
            sendTerminalResizeAccepted(session: session, on: connection)
        } catch {
            sendError(
                statusCode: 500,
                code: "terminal_resize_failed",
                message: "Failed to resize terminal: \(error.localizedDescription)",
                details: ["sessionId": .string(sessionID)],
                on: connection
            )
        }
    }

    func handleTerminalEvents(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        guard let session = runSessions[sessionID] else {
            sendError(statusCode: 404, code: "session_not_found", message: "Session not found", on: connection)
            return
        }
        guard let cursor = validatedTerminalEventsCursor(request: request, sessionID: sessionID, on: connection) else {
            return
        }
        if let staleDetails = session.staleCursorDetails(for: cursor) {
            sendError(
                statusCode: 409,
                code: "terminal_events_cursor_stale",
                message: "Requested cursor is older than retained terminal event history",
                details: staleDetails,
                on: connection
            )
            return
        }

        let events = session.events.filter { event in
            event.seq > cursor && HTTPServerUtilities.isTerminalNamespaceEvent(event.type)
        }
        let nextCursor = events.last?.seq ?? cursor
        sendJSON(
            statusCode: 200,
            payload: TerminalEventsResponse(
                sessionID: sessionID,
                terminalID: session.terminalID,
                nextCursor: nextCursor,
                events: events
            ),
            on: connection
        )
    }

    func startTmuxOutputStream(for session: RunSession) throws {
        guard let tmuxSessionName = session.tmuxSessionName else { return }
        guard session.tmuxOutputSession == nil else { return }

        let controlSession = try tmuxManager.startControlSession(name: tmuxSessionName)
        bindTmuxControlSession(controlSession, to: session)
    }

    func stopTmuxOutputStream(for session: RunSession, terminateProcess: Bool) {
        guard let controlSession = session.tmuxOutputSession else {
            session.tmuxOutputBuffer.removeAll(keepingCapacity: false)
            session.tmuxExitMarkerCarry = Data()
            return
        }

        controlSession.stdout.readabilityHandler = nil
        controlSession.stderr.readabilityHandler = nil
        try? controlSession.stdin.close()
        if terminateProcess, controlSession.process.isRunning {
            controlSession.process.terminate()
        }
        session.tmuxOutputSession = nil
        session.tmuxOutputBuffer.removeAll(keepingCapacity: false)
        session.tmuxExitMarkerCarry = Data()
        session.markDirty()
    }

    func drainTmuxControlBuffer(for session: RunSession) {
        while let newlineIndex = session.tmuxOutputBuffer.firstIndex(of: 0x0A) {
            let lineData = session.tmuxOutputBuffer[..<newlineIndex]
            session.tmuxOutputBuffer.removeSubrange(...newlineIndex)
            guard var line = String(data: lineData, encoding: .utf8) else { continue }
            if line.last == "\r" {
                line.removeLast()
            }
            guard let outputChunk = HTTPServerUtilities.parseTmuxControlOutputLine(line) else { continue }
            processTmuxOutputChunk(outputChunk, for: session)
        }
    }

    func processTmuxOutputChunk(_ chunk: Data, for session: RunSession) {
        guard !chunk.isEmpty else { return }
        let extraction = HTTPServerUtilities.extractExitMarkers(from: chunk, carry: session.tmuxExitMarkerCarry)
        session.tmuxExitMarkerCarry = extraction.carry

        if !extraction.display.isEmpty {
            session.appendTerminalOutput(chunk: extraction.display, stream: .stdout)
        }

        for exitCode in extraction.exitCodes where session.awaitingExitMarker {
            session.awaitingExitMarker = false
            session.markStatus(exitCode == 0 ? .completed : .failed)
            session.appendTerminalExit(exitCode: exitCode)
            session.appendTerminalStatus(.exited)
            session.appendTerminalClosed(exitCode: exitCode, reason: "tmux-exit")
            session.appendText(
                type: exitCode == 0 ? .info : .error,
                message: "tmux-command-exit status=\(exitCode)"
            )
        }
    }
}
