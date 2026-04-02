import ChatCore
import Foundation
import Observation
import ServerClient
import ServerProtocol

/// Shared conversation store for both Mac and iOS clients.
/// Manages connection, session list, active conversation, streaming, and approvals
/// by delegating to `ServerClient`.
@MainActor
@Observable
public final class AppStore {
    // MARK: - Nested Types

    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    public struct PendingApprovalRequest: Identifiable, Equatable, Sendable {
        public let sessionID: String
        public let requestID: String
        public let prompt: String

        public var id: String { requestID }

        public init(sessionID: String, requestID: String, prompt: String) {
            self.sessionID = sessionID
            self.requestID = requestID
            self.prompt = prompt
        }
    }

    public struct PendingInputRequest: Identifiable, Equatable, Sendable {
        public let sessionID: String
        public let requestID: String
        public let prompt: String

        public var id: String { requestID }

        public init(sessionID: String, requestID: String, prompt: String) {
            self.sessionID = sessionID
            self.requestID = requestID
            self.prompt = prompt
        }
    }

    // MARK: - Published State

    public private(set) var connectionState: ConnectionState = .disconnected
    public var connectionMessage: String?
    public let sessionListStore: SessionListStore
    public let conversationStore: ConversationStore
    public var composerText = ""
    public var composerAttachments: [ComposerAttachment] = []
    public var pendingApprovalRequest: PendingApprovalRequest?
    public var pendingInputRequest: PendingInputRequest?
    public var approvalNote = ""
    public var inputResponseText = ""

    // MARK: - Private

    private let client: ServerClient
    private var baseURL: URL?
    private var authToken: String?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    public init(client: ServerClient = ServerClient()) {
        self.client = client
        self.sessionListStore = SessionListStore()
        self.conversationStore = ConversationStore()
    }

    // MARK: - Connection

    public func connect(to url: URL, authToken: String? = nil) async {
        baseURL = url
        self.authToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        connectionState = .connecting
        connectionMessage = nil

        do {
            _ = try await client.health(baseURL: url)
            connectionState = .connected
            await reloadSessions()
        } catch {
            connectionState = .failed("Connect failed: \(error.localizedDescription)")
        }
    }

    public func disconnect() async {
        streamTask?.cancel()
        streamTask = nil
        await conversationStore.deactivate()
        resetPendingInteractiveState()
        connectionState = .disconnected
        connectionMessage = nil
        baseURL = nil
        authToken = nil
    }

    // MARK: - Session Management

    public func reloadSessions() async {
        guard case .connected = connectionState, let baseURL else { return }

        do {
            let response = try await client.listConversationSessions(
                baseURL: baseURL,
                authToken: authToken
            )
            await sessionListStore.replace(with: response.sessions)
        } catch {
            applyAuthFailureIfNeeded(error)
            sessionListStore.markFailure(conversationErrorMessage(prefix: "Session refresh failed", error: error))
        }
    }

    public func createSession(
        title: String = "New Session",
        harnessType: HarnessType = .codex,
        model: String = "gpt-5-codex"
    ) async {
        guard case .connected = connectionState, let baseURL else { return }

        do {
            let response = try await client.createConversationSession(
                baseURL: baseURL,
                authToken: authToken,
                request: SessionCreateRequest(
                    title: title,
                    harnessType: harnessType,
                    model: model
                )
            )
            await sessionListStore.upsert(response.session)
            await selectSession(response.session.id)
        } catch {
            applyAuthFailureIfNeeded(error)
            connectionMessage = conversationErrorMessage(prefix: "Create session failed", error: error)
        }
    }

    public func selectSession(_ sessionID: String?) async {
        streamTask?.cancel()
        streamTask = nil
        sessionListStore.select(sessionID: sessionID)
        resetPendingInteractiveState()

        guard let sessionID else {
            await conversationStore.deactivate()
            return
        }

        guard case .connected = connectionState, let baseURL else { return }

        do {
            let response = try await client.resumeConversationSession(
                baseURL: baseURL,
                sessionID: sessionID,
                authToken: authToken
            )
            await conversationStore.activate(
                sessionID: sessionID,
                history: response.messages,
                cursor: response.nextCursor?.sequence ?? 0
            )
            syncPendingInteractiveRequests(from: response.messages, sessionID: sessionID)
            startStreaming(sessionID: sessionID)
        } catch {
            applyAuthFailureIfNeeded(error)
            await conversationStore.markStreamingFailure(
                conversationErrorMessage(prefix: "Resume failed", error: error)
            )
        }
    }

    public func archiveSession(_ sessionID: String) async {
        guard case .connected = connectionState, let baseURL else { return }
        do {
            let response = try await client.archiveConversationSession(
                baseURL: baseURL,
                sessionID: sessionID,
                authToken: authToken
            )
            await sessionListStore.upsert(response.session)
            if sessionListStore.selectedSessionID == sessionID {
                await selectSession(nil)
            }
        } catch {
            applyAuthFailureIfNeeded(error)
            connectionMessage = conversationErrorMessage(prefix: "Archive failed", error: error)
        }
    }

    public func deleteSession(_ sessionID: String) async {
        guard case .connected = connectionState, let baseURL else { return }
        do {
            _ = try await client.deleteConversationSession(
                baseURL: baseURL,
                sessionID: sessionID,
                authToken: authToken
            )
            await sessionListStore.delete(sessionID: sessionID)
            if sessionListStore.selectedSessionID == sessionID {
                await selectSession(nil)
            }
        } catch {
            applyAuthFailureIfNeeded(error)
            connectionMessage = conversationErrorMessage(prefix: "Delete failed", error: error)
        }
    }

    // MARK: - Attachments

    public func addAttachment(_ attachment: ComposerAttachment) {
        guard !composerAttachments.contains(attachment) else { return }
        composerAttachments.append(attachment)
    }

    public func removeAttachment(_ attachment: ComposerAttachment) {
        composerAttachments.removeAll { $0 == attachment }
    }

    // MARK: - Messaging

    public func sendComposerMessage() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let sessionID = conversationStore.activeSessionID else { return }
        guard case .connected = connectionState, let baseURL else { return }
        let clientMessageID = UUID().uuidString

        composerText = ""
        composerAttachments.removeAll()
        await conversationStore.appendLocalUserMessage(text, messageID: clientMessageID)

        do {
            _ = try await client.sendConversationMessage(
                baseURL: baseURL,
                sessionID: sessionID,
                text: text,
                authToken: authToken,
                clientMessageID: clientMessageID
            )
        } catch {
            applyAuthFailureIfNeeded(error)
            connectionMessage = conversationErrorMessage(prefix: "Send failed", error: error)
        }
    }

    // MARK: - Approvals & Input

    public func submitApproval(decision: ConversationDecision) async {
        guard let pendingApprovalRequest else { return }
        guard case .connected = connectionState, let baseURL else { return }

        do {
            _ = try await client.sendConversationApproval(
                baseURL: baseURL,
                sessionID: pendingApprovalRequest.sessionID,
                requestID: pendingApprovalRequest.requestID,
                decision: decision,
                authToken: authToken,
                note: approvalNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            self.pendingApprovalRequest = nil
            approvalNote = ""
        } catch {
            applyAuthFailureIfNeeded(error)
            connectionMessage = conversationErrorMessage(prefix: "Approval failed", error: error)
        }
    }

    public func submitUserInput() async {
        guard let pendingInputRequest else { return }
        guard case .connected = connectionState, let baseURL else { return }

        let value = inputResponseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        do {
            _ = try await client.sendConversationUserInput(
                baseURL: baseURL,
                sessionID: pendingInputRequest.sessionID,
                requestID: pendingInputRequest.requestID,
                authToken: authToken,
                value: value
            )
            self.pendingInputRequest = nil
            inputResponseText = ""
        } catch {
            applyAuthFailureIfNeeded(error)
            connectionMessage = conversationErrorMessage(prefix: "Input response failed", error: error)
        }
    }

    // MARK: - Streaming

    private func startStreaming(sessionID: String) {
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.conversationStore.beginStreaming()
            await self.conversationStore.markStreaming()

            guard let baseURL = self.baseURL else { return }
            let cursor = self.conversationStore.nextCursor

            let stream = await self.client.streamConversationEvents(
                baseURL: baseURL,
                sessionID: sessionID,
                authToken: self.authToken,
                cursor: cursor
            )

            do {
                for try await event in stream {
                    await self.conversationStore.apply(event: event)
                    await self.handleConversationEvent(event)
                }
                await self.conversationStore.endStreaming()
            } catch {
                self.applyAuthFailureIfNeeded(error)
                await self.conversationStore.markStreamingFailure(
                    self.conversationErrorMessage(prefix: "Stream failed", error: error)
                )
            }
        }
    }

    private func handleConversationEvent(_ event: ConversationEventEnvelope) async {
        switch event.type {
        case .sessionUpdated, .sessionStatus:
            if let session = decodeSession(from: event.payload) {
                await sessionListStore.upsert(session)
            }
        case .messageUpsert, .messageBlockUpdated:
            if let message = decodeMessage(from: event.payload) {
                processInteractiveRequests(in: message)
            }
        default:
            break
        }
    }

}

public extension AppStore {
    func updateAuthToken(_ authToken: String?) {
        self.authToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension AppStore {
    func processInteractiveRequests(in message: Message) {
        for block in message.blocks {
            switch block.kind {
            case .toolCall:
                let requestID = block.approvalRequestID
                if let requestID {
                    let prompt = block.summary ?? "Approve this tool call?"
                    pendingApprovalRequest = PendingApprovalRequest(
                        sessionID: message.sessionID,
                        requestID: requestID,
                        prompt: prompt
                    )
                }
            case .userInputRequest:
                if let requestID = block.userInputRequestID {
                    let prompt = block.userInputPrompt ?? "Provide required input."
                    pendingInputRequest = PendingInputRequest(
                        sessionID: message.sessionID,
                        requestID: requestID,
                        prompt: prompt
                    )
                }
            default:
                break
            }
        }
    }

    func decodeSession(from payload: JSONValue?) -> Session? {
        guard let payload else { return nil }
        if let nested = payload["session"] {
            return try? ServerJSONCoding.decodeValue(Session.self, from: nested)
        }
        if case .object = payload {
            return try? ServerJSONCoding.decodeValue(Session.self, from: payload)
        }
        return nil
    }

    func decodeMessage(from payload: JSONValue?) -> Message? {
        guard let payload else { return nil }
        if let nested = payload["message"] {
            return try? ServerJSONCoding.decodeValue(Message.self, from: nested)
        }
        if case .object = payload {
            return try? ServerJSONCoding.decodeValue(Message.self, from: payload)
        }
        return nil
    }

    func applyAuthFailureIfNeeded(_ error: Error) {
        guard isUnauthorized(error) else { return }
        connectionState = .failed("Conversation auth failed (401). Update pairing token in settings.")
    }

    func conversationErrorMessage(prefix: String, error: Error) -> String {
        if isUnauthorized(error) {
            return "\(prefix): Conversation auth failed (401). Update pairing token in settings."
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    func isUnauthorized(_ error: Error) -> Bool {
        guard case ServerClientError.badStatus(let statusCode) = error else { return false }
        return statusCode == 401
    }
}

extension AppStore {
    func syncPendingInteractiveRequests(from messages: [Message], sessionID: String) {
        var pendingApproval: PendingApprovalRequest?
        var pendingInput: PendingInputRequest?

        for message in messages.reversed() where message.sessionID == sessionID {
            for block in message.blocks.reversed() {
                if pendingApproval == nil, let requestID = block.approvalRequestID {
                    pendingApproval = PendingApprovalRequest(
                        sessionID: sessionID,
                        requestID: requestID,
                        prompt: block.summary ?? "Approve this tool call?"
                    )
                }

                if pendingInput == nil, let requestID = block.userInputRequestID {
                    pendingInput = PendingInputRequest(
                        sessionID: sessionID,
                        requestID: requestID,
                        prompt: block.userInputPrompt ?? "Provide required input."
                    )
                }

                if pendingApproval != nil, pendingInput != nil {
                    break
                }
            }

            if pendingApproval != nil, pendingInput != nil {
                break
            }
        }

        pendingApprovalRequest = pendingApproval
        pendingInputRequest = pendingInput
    }

    func resetPendingInteractiveState() {
        pendingApprovalRequest = nil
        pendingInputRequest = nil
        approvalNote = ""
        inputResponseText = ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
