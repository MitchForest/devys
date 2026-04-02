import Agents
import ChatCore
import Foundation
import ServerProtocol

// Resolve ambiguity between ChatCore.SessionStatus and ServerProtocol.SessionStatus.
private typealias SessionStatus = ChatCore.SessionStatus

/// Manages a single conversation session: agent process + event log + message state.
///
/// Each conversation has its own `DevysAgent` running in a tmux session,
/// an append-only event log, and materialized messages for fast resume.
actor ConversationRunSession {
    let id: String
    private(set) var metadata: Session
    private(set) var messages: [Message] = []
    private let eventLog: ConversationEventLog
    private let translator: AgentEventTranslator
    private var agent: DevysAgent?
    private var eventForwardingTask: Task<Void, Never>?
    private var pendingApprovals: [String: AgentApproval] = [:]
    private var onPersistenceUpdate: (@Sendable (Session, [Message]) -> Void)?
    private var clientMessageIndex: [String: String] = [:]

    /// Live-event subscribers keyed by subscriber ID.
    private var eventSubscribers: [UUID: @Sendable (ConversationEventEnvelope) -> Void] = [:]

    /// Add a live-event subscriber and return its token.
    func addEventSubscriber(
        _ handler: @escaping @Sendable (ConversationEventEnvelope) -> Void
    ) -> UUID {
        let subscriberID = UUID()
        eventSubscribers[subscriberID] = handler
        return subscriberID
    }

    /// Remove a previously-registered subscriber.
    func removeEventSubscriber(_ subscriberID: UUID) {
        eventSubscribers.removeValue(forKey: subscriberID)
    }

    func setPersistenceHandler(
        _ handler: @escaping @Sendable (Session, [Message]) -> Void
    ) {
        onPersistenceUpdate = handler
        persistSnapshot()
    }

    init(
        id: String,
        metadata: Session,
        eventLog: ConversationEventLog,
        translator: AgentEventTranslator,
        restoredMessages: [Message] = []
    ) {
        self.id = id
        self.metadata = metadata
        self.eventLog = eventLog
        self.translator = translator
        self.messages = restoredMessages
    }

    // MARK: - Lifecycle

    /// Start the agent process and begin forwarding events.
    func start(agent: DevysAgent) async throws {
        self.agent = agent
        try await agent.start()

        metadata = Session(
            id: metadata.id,
            title: metadata.title,
            harnessType: metadata.harnessType,
            model: metadata.model,
            workspaceRoot: metadata.workspaceRoot,
            branch: metadata.branch,
            status: .streaming,
            createdAt: metadata.createdAt,
            updatedAt: .now,
            lastMessagePreview: metadata.lastMessagePreview,
            unreadCount: metadata.unreadCount
        )

        let agentEvents = await agent.events
        eventForwardingTask = Task { [weak self] in
            guard let self else { return }
            for await agentEvent in agentEvents {
                await self.processAgentEvent(agentEvent)
            }
            await self.updateStatus(.idle)
        }
    }

    /// Stop the agent and clean up.
    func stop() async {
        eventForwardingTask?.cancel()
        eventForwardingTask = nil
        await agent?.stop()
        agent = nil
        await updateStatus(.idle)
    }

    // MARK: - User Actions

    /// Send a user message to the agent.
    func sendMessage(_ text: String, clientMessageID: String? = nil) async throws -> Message {
        if let clientMessageID,
           let existingMessageID = clientMessageIndex[clientMessageID],
           let existing = messages.first(where: { $0.id == existingMessageID })
        {
            return existing
        }

        let userMessage = await translator.createUserMessage(text: text, explicitID: clientMessageID)
        messages.append(userMessage)
        if let clientMessageID {
            clientMessageIndex[clientMessageID] = userMessage.id
        }

        let payload = encodeMessage(userMessage)
        let envelope = try await eventLog.append(
            sessionID: id,
            type: .messageUpsert,
            payload: payload
        )
        broadcast(envelope)
        persistSnapshot()

        guard let agent else { return userMessage }

        if metadata.harnessType == .codex {
            _ = try await agent.send(
                text,
                to: id,
                cwd: metadata.workspaceRoot ?? FileManager.default.currentDirectoryPath
            )
        } else {
            try await agent.query(text)
        }

        await updateStatus(.streaming)
        return userMessage
    }

    /// Respond to an approval request.
    func respondToApproval(requestID: String, decision: ConversationDecision, note _: String?) async throws {
        guard let agent else { return }
        let agentDecision: AgentApprovalDecision = decision == .approve ? .approve : .deny

        guard let approval = pendingApprovals.removeValue(forKey: requestID) else {
            // No stored approval — should not normally happen, but log and bail.
            return
        }
        try await agent.respondToApproval(approval, decision: agentDecision)
    }

    /// Respond to a user input request.
    func respondToUserInput(requestID: String, value: String) async throws {
        guard let agent else { return }
        try await agent.respondToUserInput(requestId: requestID, answers: [value])
    }

    // MARK: - Metadata

    func rename(to title: String) {
        metadata = Session(
            id: metadata.id,
            title: title,
            harnessType: metadata.harnessType,
            model: metadata.model,
            workspaceRoot: metadata.workspaceRoot,
            branch: metadata.branch,
            status: metadata.status,
            createdAt: metadata.createdAt,
            updatedAt: .now,
            lastMessagePreview: metadata.lastMessagePreview,
            unreadCount: metadata.unreadCount
        )
        persistSnapshot()
    }

    func archive() async {
        await stop()
        metadata = Session(
            id: metadata.id,
            title: metadata.title,
            harnessType: metadata.harnessType,
            model: metadata.model,
            workspaceRoot: metadata.workspaceRoot,
            branch: metadata.branch,
            status: .archived,
            createdAt: metadata.createdAt,
            updatedAt: .now,
            archivedAt: .now,
            lastMessagePreview: metadata.lastMessagePreview,
            unreadCount: metadata.unreadCount
        )
        persistSnapshot()
    }

    // MARK: - Event Log Access

    /// Replay events for a connecting client.
    func replayEvents(afterSequence cursor: UInt64) async -> [ConversationEventEnvelope] {
        await eventLog.replay(afterSequence: cursor)
    }

    /// Current sequence number for cursor-based streaming.
    var currentSequence: UInt64 {
        get async { await eventLog.currentSequence }
    }

    // MARK: - Private

    private func processAgentEvent(_ agentEvent: AgentEvent) async {
        // Stash approval objects so we can look them up when the client responds.
        if case .approvalRequired(let approval) = agentEvent {
            pendingApprovals[approval.id] = approval
        }

        let result = await translator.translate(agentEvent)

        if let message = result.updatedMessage {
            upsertMessage(message)
        }

        for (type, payload) in result.events {
            do {
                let envelope = try await eventLog.append(
                    sessionID: id,
                    type: type,
                    payload: payload
                )
                broadcast(envelope)
            } catch {
                // Log but don't crash — event log write failure shouldn't kill the session
            }
        }
    }

    private func broadcast(_ event: ConversationEventEnvelope) {
        for subscriber in eventSubscribers.values {
            subscriber(event)
        }
    }

    private func upsertMessage(_ message: Message) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
        }

        metadata = Session(
            id: metadata.id,
            title: metadata.title,
            harnessType: metadata.harnessType,
            model: metadata.model,
            workspaceRoot: metadata.workspaceRoot,
            branch: metadata.branch,
            status: metadata.status,
            createdAt: metadata.createdAt,
            updatedAt: .now,
            lastMessagePreview: message.text.prefix(100).description,
            unreadCount: metadata.unreadCount
        )
        persistSnapshot()
    }

    private func updateStatus(_ status: SessionStatus) {
        metadata = Session(
            id: metadata.id,
            title: metadata.title,
            harnessType: metadata.harnessType,
            model: metadata.model,
            workspaceRoot: metadata.workspaceRoot,
            branch: metadata.branch,
            status: status,
            createdAt: metadata.createdAt,
            updatedAt: .now,
            lastMessagePreview: metadata.lastMessagePreview,
            unreadCount: metadata.unreadCount
        )
        persistSnapshot()
    }

    private func encodeMessage(_ message: Message) -> JSONValue? {
        guard let data = try? ServerJSONCoding.makeEncoder().encode(message),
              let json = try? ServerJSONCoding.makeDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return .object(["message": json])
    }

    private func persistSnapshot() {
        onPersistenceUpdate?(metadata, messages)
    }
}
