import ChatCore
import Foundation
import Network
import ServerProtocol

private final class ConversationReplayBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var replayInFlight = true
    private var buffered: [ConversationEventEnvelope] = []

    /// Returns true when the caller should send immediately.
    func shouldSendImmediatelyOrBuffer(_ event: ConversationEventEnvelope) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard replayInFlight else { return true }
        buffered.append(event)
        return false
    }

    func finishReplayAndDrain() -> [ConversationEventEnvelope] {
        lock.lock()
        defer { lock.unlock() }

        replayInFlight = false
        let drained = buffered.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence {
                return lhs.sequence < rhs.sequence
            }
            return lhs.eventID < rhs.eventID
        }
        buffered.removeAll(keepingCapacity: true)
        return drained
    }
}

extension HTTPServer {
    func authorizeConversationRequest(_ request: HTTPRequest, on connection: NWConnection) -> Bool {
        let activeTokens = activeConversationAuthTokens()
        // Allow bootstrap access when no active pairing tokens exist yet.
        guard !activeTokens.isEmpty else { return true }

        guard let bearerToken = request.bearerAuthorizationToken else {
            sendError(
                statusCode: 401,
                code: "conversation_auth_required",
                message: "Conversation endpoints require a valid pairing bearer token",
                on: connection
            )
            return false
        }

        guard activeTokens.contains(bearerToken) else {
            sendError(
                statusCode: 401,
                code: "conversation_auth_invalid",
                message: "Pairing bearer token is invalid or revoked",
                on: connection
            )
            return false
        }

        return true
    }

    private func activeConversationAuthTokens() -> Set<String> {
        let activePairingIDs = pairings.values
            .filter { $0.status == .active }
            .map(\.id)
        return Set(
            activePairingIDs.compactMap { pairingID in
                pairingTokens[pairingID]?.nilIfEmpty
            }
        )
    }

    func endConversationStream(for connection: NWConnection) {
        let key = ObjectIdentifier(connection)

        let existing: ConversationStreamRegistration?
        conversationStreamLock.lock()
        existing = conversationStreams.removeValue(forKey: key)
        conversationStreamLock.unlock()

        guard let existing else { return }
        existing.heartbeatTask.cancel()

        Task { [conversationRuntime] in
            guard let runSession = await conversationRuntime.session(existing.sessionID) else { return }
            await runSession.removeEventSubscriber(existing.subscriberID)
        }
    }

    private func registerConversationStream(
        connection: NWConnection,
        sessionID: String,
        subscriberID: UUID,
        heartbeatTask: Task<Void, Never>
    ) {
        let key = ObjectIdentifier(connection)
        let registration = ConversationStreamRegistration(
            sessionID: sessionID,
            subscriberID: subscriberID,
            heartbeatTask: heartbeatTask
        )

        let previous: ConversationStreamRegistration?
        conversationStreamLock.lock()
        previous = conversationStreams.updateValue(registration, forKey: key)
        conversationStreamLock.unlock()

        guard let previous else { return }
        previous.heartbeatTask.cancel()

        Task { [conversationRuntime] in
            guard let runSession = await conversationRuntime.session(previous.sessionID) else { return }
            await runSession.removeEventSubscriber(previous.subscriberID)
        }
    }

    // MARK: - GET Handlers

    func handleConversationSessionsList(request: HTTPRequest, on connection: NWConnection) {
        Task {
            let includeArchived = request.query["includeArchived"] == "1"
            let sessions = await conversationRuntime.listSessions(includeArchived: includeArchived)
            let response = SessionListResponse(sessions: sessions)
            sendJSON(response, on: connection)
        }
    }

    func handleConversationSessionResume(sessionID: String, on connection: NWConnection) {
        Task {
            guard let result = await conversationRuntime.resumeSession(sessionID) else {
                sendError(404, message: "Session not found", on: connection)
                return
            }
            let response = SessionResumeResponse(
                session: result.session,
                messages: result.messages,
                nextCursor: result.cursor
            )
            sendJSON(response, on: connection)
        }
    }

    func handleConversationSessionStream(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let runSession = await conversationRuntime.session(sessionID) else {
                sendError(404, message: "Session not found", on: connection)
                return
            }

            let cursorSeq = request.query["cursor"].flatMap { UInt64($0) } ?? 0

            // Send HTTP headers for NDJSON streaming
            let headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: application/x-ndjson",
                "Transfer-Encoding: chunked",
                "Cache-Control: no-cache",
                "Connection: keep-alive",
                "",
                "",
            ].joined(separator: "\r\n")
            connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in })

            // Register for live events first and buffer them while replay is in-flight.
            let replayBuffer = ConversationReplayBuffer()
            let subscriberID = await runSession.addEventSubscriber { [weak self, weak connection] event in
                guard let self, let connection else { return }
                if replayBuffer.shouldSendImmediatelyOrBuffer(event) {
                    self.sendNDJSONEvent(event, on: connection)
                }
            }

            let heartbeatTask = startHeartbeat(sessionID: sessionID, on: connection)
            registerConversationStream(
                connection: connection,
                sessionID: sessionID,
                subscriberID: subscriberID,
                heartbeatTask: heartbeatTask
            )

            // Replay buffered events
            let replayEvents = await runSession.replayEvents(afterSequence: cursorSeq)
            for event in replayEvents {
                sendNDJSONEvent(event, on: connection)
            }

            let bufferedLiveEvents = replayBuffer.finishReplayAndDrain()
            for event in bufferedLiveEvents {
                sendNDJSONEvent(event, on: connection)
            }
        }
    }

    // MARK: - POST Handlers

    func handleConversationSessionCreate(request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let createReq = try? ServerJSONCoding.makeDecoder().decode(
                SessionCreateRequest.self,
                from: request.body
            )
            else {
                sendError(400, message: "Invalid request body", on: connection)
                return
            }

            do {
                let session = try await conversationRuntime.createSession(
                    title: createReq.title,
                    harnessType: createReq.harnessType,
                    model: createReq.model,
                    workspaceRoot: createReq.workspaceRoot,
                    branch: createReq.branch
                )
                let response = SessionCreateResponse(session: session)
                sendJSON(response, on: connection)
            } catch {
                sendError(500, message: "Failed to create session: \(error.localizedDescription)", on: connection)
            }
        }
    }

    func handleConversationSessionArchive(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let archiveReq = try? ServerJSONCoding.makeDecoder().decode(
                SessionArchiveRequest.self,
                from: request.body
            )
            else {
                sendError(400, message: "Invalid request body", on: connection)
                return
            }

            if archiveReq.archived {
                guard let session = await conversationRuntime.archiveSession(sessionID) else {
                    sendError(404, message: "Session not found", on: connection)
                    return
                }
                let response = SessionArchiveResponse(session: session)
                sendJSON(response, on: connection)
            } else {
                // Unarchive not yet implemented
                sendError(501, message: "Unarchive not implemented", on: connection)
            }
        }
    }

    func handleConversationSessionRename(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let renameReq = try? ServerJSONCoding.makeDecoder().decode(
                SessionRenameRequest.self,
                from: request.body
            )
            else {
                sendError(400, message: "Invalid request body", on: connection)
                return
            }

            guard let session = await conversationRuntime.renameSession(sessionID, title: renameReq.title) else {
                sendError(404, message: "Session not found", on: connection)
                return
            }
            let response = SessionRenameResponse(session: session)
            sendJSON(response, on: connection)
        }
    }

    func handleConversationSessionDelete(sessionID: String, on connection: NWConnection) {
        Task {
            await conversationRuntime.deleteSession(sessionID)
            let response = SessionDeleteResponse(
                deleted: true,
                sessionID: sessionID
            )
            sendJSON(response, on: connection)
        }
    }

    func handleConversationMessage(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let messageReq = try? ServerJSONCoding.makeDecoder().decode(
                ConversationUserMessageRequest.self,
                from: request.body
            )
            else {
                sendError(400, message: "Invalid request body", on: connection)
                return
            }

            do {
                let message = try await conversationRuntime.sendMessage(
                    sessionID,
                    text: messageReq.text,
                    clientMessageID: messageReq.clientMessageID
                )
                let response = ConversationUserMessageResponse(accepted: true, message: message)
                sendJSON(response, on: connection)
            } catch {
                sendError(500, message: "Send failed: \(error.localizedDescription)", on: connection)
            }
        }
    }

    func handleConversationApproval(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let approvalReq = try? ServerJSONCoding.makeDecoder().decode(
                      ConversationApprovalResponseRequest.self, from: request.body
                  )
            else {
                sendError(400, message: "Invalid request body", on: connection)
                return
            }

            do {
                try await conversationRuntime.respondToApproval(
                    sessionID: sessionID,
                    requestID: approvalReq.requestID,
                    decision: approvalReq.decision,
                    note: approvalReq.note
                )
                let response = ConversationActionResponse(accepted: true)
                sendJSON(response, on: connection)
            } catch {
                sendError(500, message: "Approval failed: \(error.localizedDescription)", on: connection)
            }
        }
    }

    func handleConversationUserInput(sessionID: String, request: HTTPRequest, on connection: NWConnection) {
        Task {
            guard let inputReq = try? ServerJSONCoding.makeDecoder().decode(
                      ConversationUserInputResponseRequest.self, from: request.body
                  )
            else {
                sendError(400, message: "Invalid request body", on: connection)
                return
            }

            do {
                try await conversationRuntime.respondToUserInput(
                    sessionID: sessionID,
                    requestID: inputReq.requestID,
                    value: inputReq.value
                )
                let response = ConversationActionResponse(accepted: true)
                sendJSON(response, on: connection)
            } catch {
                sendError(500, message: "Input response failed: \(error.localizedDescription)", on: connection)
            }
        }
    }

    // MARK: - Helpers

    private func sendNDJSONEvent(_ event: ConversationEventEnvelope, on connection: NWConnection) {
        guard let data = try? ServerJSONCoding.makeEncoder().encode(event),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"

        let chunkSize = String(format: "%x\r\n", line.utf8.count)
        let chunk = chunkSize + line + "\r\n"
        connection.send(
            content: chunk.data(using: .utf8),
            completion: .contentProcessed { [weak self, weak connection] error in
                guard error != nil, let self, let connection else { return }
                self.endConversationStream(for: connection)
            }
        )
    }

    private func startHeartbeat(sessionID: String, on connection: NWConnection) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let heartbeat = ConversationEventEnvelope(
                    sessionID: sessionID,
                    sequence: 0,
                    type: .streamHeartbeat
                )
                sendNDJSONEvent(heartbeat, on: connection)
            }
        }
    }

    private func sendJSON<T: Encodable>(_ value: T, on connection: NWConnection) {
        guard let data = try? ServerJSONCoding.makeEncoder().encode(value) else {
            sendError(500, message: "Encoding failed", on: connection)
            return
        }
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in })
    }

    private func sendError(_ code: Int, message: String, on connection: NWConnection) {
        let body = "{\"error\":\"\(message)\"}"
        let headers = [
            "HTTP/1.1 \(code) Error",
            "Content-Type: application/json",
            "Content-Length: \(body.utf8.count)",
            "",
            "",
        ].joined(separator: "\r\n")
        let response = headers + body
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
    }
}
