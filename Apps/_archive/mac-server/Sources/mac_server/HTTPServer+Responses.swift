import Foundation
import Network
import ServerProtocol

extension HTTPServer {
    func sendHealth(on connection: NWConnection) {
        sendJSON(
            statusCode: 200,
            payload: HealthResponse(serverName: serverName, version: version),
            on: connection
        )
    }

    func sendCapabilities(on connection: NWConnection) {
        sendJSON(
            statusCode: 200,
            payload: ServerCapabilitiesResponse(
                tmuxAvailable: tmuxManager.isAvailable,
                claudeAvailable: HTTPServerUtilities.commandExists("claude"),
                codexAvailable: HTTPServerUtilities.commandExists("codex")
            ),
            on: connection
        )
    }

    func handleListSessions(on connection: NWConnection) {
        let sessions = runSessions.values
            .map(\.summary)
            .sorted { $0.updatedAt > $1.updatedAt }
        sendJSON(
            statusCode: 200,
            payload: ListSessionsResponse(sessions: sessions),
            on: connection
        )
    }

    func sendJSON<T: Encodable>(statusCode: Int, payload: T, on connection: NWConnection) {
        do {
            let jsonData = try ServerJSONCoding.makeEncoder().encode(payload)
            var response = Data("HTTP/1.1 \(statusCode) \(HTTPServerUtilities.statusText(for: statusCode))\r\n".utf8)
            response.append(Data("Content-Type: application/json\r\n".utf8))
            response.append(Data("Content-Length: \(jsonData.count)\r\n".utf8))
            response.append(Data("Connection: close\r\n\r\n".utf8))
            response.append(jsonData)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendStatus(500, body: "Encoding Error", on: connection)
        }
    }

    func sendStatus(_ statusCode: Int, body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        var response = Data("HTTP/1.1 \(statusCode) \(HTTPServerUtilities.statusText(for: statusCode))\r\n".utf8)
        response.append(Data("Content-Type: text/plain; charset=utf-8\r\n".utf8))
        response.append(Data("Content-Length: \(bodyData.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func startStream(on connection: NWConnection) {
        var headers = Data("HTTP/1.1 200 OK\r\n".utf8)
        headers.append(Data("Content-Type: application/x-ndjson\r\n".utf8))
        headers.append(Data("Cache-Control: no-cache\r\n".utf8))
        headers.append(Data("Connection: keep-alive\r\n".utf8))
        headers.append(Data("Transfer-Encoding: chunked\r\n\r\n".utf8))

        connection.send(content: headers, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }

            let id = ObjectIdentifier(connection)
            let streamSessionID = UUID().uuidString
            let session = StreamSession(
                connection: connection,
                queue: self.queue,
                nextEvent: { [weak self] type, message in
                    guard let self else {
                        return StreamEventEnvelope.text(
                            seq: 0,
                            type: type,
                            message: message,
                            sessionID: streamSessionID
                        )
                    }
                    let event = StreamEventEnvelope.text(
                        seq: self.nextStreamEventID,
                        type: type,
                        message: message,
                        sessionID: streamSessionID
                    )
                    self.nextStreamEventID += 1
                    return event
                },
                onClose: { [weak self] in
                    self?.streamSessions.removeValue(forKey: id)
                }
            )
            self.streamSessions[id] = session
            session.start()
        })
    }

    func endStream(for connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        streamSessions[id]?.stop()
        streamSessions[id] = nil
    }

    func sendError(
        statusCode: Int,
        code: String,
        message: String,
        details: [String: JSONValue]? = nil,
        on connection: NWConnection
    ) {
        sendJSON(
            statusCode: statusCode,
            payload: APIErrorResponse(code: code, message: message, details: details),
            on: connection
        )
    }

    func decodeRunSessionRequest(_ request: HTTPRequest, on connection: NWConnection) -> RunSessionRequest? {
        do {
            return try ServerJSONCoding.makeDecoder().decode(RunSessionRequest.self, from: request.body)
        } catch {
            sendError(
                statusCode: 400,
                code: "invalid_request",
                message: "Unable to decode run session payload",
                on: connection
            )
            return nil
        }
    }

    func sendTmuxUnavailableError(on connection: NWConnection) {
        sendError(
            statusCode: 503,
            code: "tmux_unavailable",
            message: "tmux is required on this server",
            on: connection
        )
    }

    func markSessionRunFailure(_ session: RunSession, message: String) {
        session.markStatus(.failed)
        session.appendTerminalStatus(.exited)
        session.appendText(type: .error, message: message)
    }
}
