import ChatCore
import Foundation
import ServerProtocol

public extension ServerClient {
    func listConversationSessions(
        baseURL: URL,
        authToken: String? = nil,
        includeArchived: Bool = false,
        limit: Int? = nil
    ) async throws -> SessionListResponse {
        let base = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw ServerClientError.invalidURL
        }

        var queryItems = [URLQueryItem(name: "includeArchived", value: includeArchived ? "1" : "0")]
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ServerClientError.invalidURL
        }
        return try await requestJSON(
            url: url,
            method: "GET",
            body: Optional<Data>.none,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func createConversationSession(
        baseURL: URL,
        authToken: String? = nil,
        request: SessionCreateRequest
    ) async throws -> SessionCreateResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions")
        let body = try ServerJSONCoding.makeEncoder().encode(request)
        return try await requestJSON(
            url: url,
            method: "POST",
            body: body,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func archiveConversationSession(
        baseURL: URL,
        sessionID: String,
        authToken: String? = nil,
        archived: Bool = true
    ) async throws -> SessionArchiveResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)/archive")
        let body = try ServerJSONCoding.makeEncoder().encode(SessionArchiveRequest(archived: archived))
        return try await requestJSON(
            url: url,
            method: "POST",
            body: body,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func deleteConversationSession(
        baseURL: URL,
        sessionID: String,
        authToken: String? = nil
    ) async throws -> SessionDeleteResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)")
        return try await requestJSON(
            url: url,
            method: "DELETE",
            body: Optional<Data>.none,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func resumeConversationSession(
        baseURL: URL,
        sessionID: String,
        authToken: String? = nil
    ) async throws -> SessionResumeResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)/resume")
        return try await requestJSON(
            url: url,
            method: "GET",
            body: Optional<Data>.none,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func sendConversationMessage(
        baseURL: URL,
        sessionID: String,
        text: String,
        authToken: String? = nil,
        clientMessageID: String? = nil
    ) async throws -> ConversationUserMessageResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)/messages")
        let body = try ServerJSONCoding.makeEncoder().encode(
            ConversationUserMessageRequest(
                text: text,
                clientMessageID: clientMessageID
            )
        )
        return try await requestJSON(
            url: url,
            method: "POST",
            body: body,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func sendConversationApproval(
        baseURL: URL,
        sessionID: String,
        requestID: String,
        decision: ConversationDecision,
        authToken: String? = nil,
        note: String? = nil
    ) async throws -> ConversationActionResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)/approval")
        let body = try ServerJSONCoding.makeEncoder().encode(
            ConversationApprovalResponseRequest(
                requestID: requestID,
                decision: decision,
                note: note
            )
        )
        return try await requestJSON(
            url: url,
            method: "POST",
            body: body,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func sendConversationUserInput(
        baseURL: URL,
        sessionID: String,
        requestID: String,
        authToken: String? = nil,
        value: String
    ) async throws -> ConversationActionResponse {
        let url = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)/input")
        let body = try ServerJSONCoding.makeEncoder().encode(
            ConversationUserInputResponseRequest(requestID: requestID, value: value)
        )
        return try await requestJSON(
            url: url,
            method: "POST",
            body: body,
            headers: Self.conversationAuthHeaders(authToken: authToken)
        )
    }

    func streamConversationEvents(
        baseURL: URL,
        sessionID: String,
        authToken: String? = nil,
        cursor: StreamCursor?
    ) -> AsyncThrowingStream<ConversationEventEnvelope, Error> {
        let base = Self.endpoint(baseURL: baseURL, path: "v1/conversations/sessions/\(sessionID)/stream")
        let url: URL
        if let cursor, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            components.queryItems = [
                URLQueryItem(name: "cursor", value: String(cursor.sequence))
            ]
            url = components.url ?? base
        } else {
            url = base
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                    for (key, value) in Self.conversationAuthHeaders(authToken: authToken) {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ServerClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw ServerClientError.badStatus(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }

                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let data = Data(trimmed.utf8)
                        let event = try ServerJSONCoding.makeDecoder().decode(
                            ConversationEventEnvelope.self,
                            from: data
                        )
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private extension ServerClient {
    static func conversationAuthHeaders(authToken: String?) -> [String: String] {
        guard let authToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !authToken.isEmpty
        else {
            return [:]
        }
        return ["Authorization": "Bearer \(authToken)"]
    }
}
