import Agents
import ChatCore
import Foundation
import ServerProtocol

/// Top-level orchestrator for all conversation sessions.
///
/// Creates and manages `ConversationRunSession` instances, handles CRUD operations,
/// coordinates streaming, and manages persistence + recovery.
actor ConversationRuntime {
    private var sessions: [String: ConversationRunSession] = [:]
    private let store: ConversationSessionStore
    private let eventsBaseDirectory: URL

    init(store: ConversationSessionStore? = nil) {
        let resolvedStore = store ?? ConversationSessionStore()
        self.store = resolvedStore
        self.eventsBaseDirectory = resolvedStore.baseDirectory
    }

    // MARK: - Startup

    /// Load persisted sessions on server start.
    func loadPersistedSessions() async {
        let persisted = store.loadAllSessions()
        for session in persisted {
            guard session.status != .archived else { continue }

            let eventLog = ConversationEventLog(
                directory: eventsBaseDirectory,
                sessionID: session.id
            )
            do {
                try await eventLog.open()
            } catch {
                continue
            }

            let translator = AgentEventTranslator(sessionID: session.id)
            let runSession = ConversationRunSession(
                id: session.id,
                metadata: session,
                eventLog: eventLog,
                translator: translator,
                restoredMessages: store.loadMessages(sessionID: session.id)
            )
            await configurePersistence(for: runSession)
            sessions[session.id] = runSession
        }
    }

    // MARK: - CRUD

    /// List all sessions.
    func listSessions(includeArchived: Bool = false) async -> [Session] {
        var result: [Session] = []
        for (_, runSession) in sessions {
            let metadata = await runSession.metadata
            if !includeArchived && metadata.status == .archived { continue }
            result.append(metadata)
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Create a new conversation session and spawn an agent.
    func createSession(
        title: String,
        harnessType: ChatCore.HarnessType,
        model: String,
        workspaceRoot: String? = nil,
        branch: String? = nil
    ) async throws -> Session {
        let sessionID = UUID().uuidString
        let cwd = workspaceRoot ?? FileManager.default.currentDirectoryPath

        let metadata = Session(
            id: sessionID,
            title: title,
            harnessType: harnessType,
            model: model,
            workspaceRoot: workspaceRoot,
            branch: branch,
            status: .idle,
            createdAt: .now,
            updatedAt: .now
        )

        let eventLog = ConversationEventLog(
            directory: eventsBaseDirectory,
            sessionID: sessionID
        )
        try await eventLog.open()

        let translator = AgentEventTranslator(sessionID: sessionID)
        let runSession = ConversationRunSession(
            id: sessionID,
            metadata: metadata,
            eventLog: eventLog,
            translator: translator
        )
        await configurePersistence(for: runSession)

        let resolvedModel = Agents.LLMModel.from(id: model)
        let agent = await DevysAgent(
            harnessType: Agents.HarnessType(rawValue: harnessType.rawValue) ?? .codex,
            cwd: cwd,
            model: resolvedModel
        )
        try await runSession.start(agent: agent)

        sessions[sessionID] = runSession
        try store.saveSession(await runSession.metadata)

        return await runSession.metadata
    }

    /// Resume a session — return metadata, messages, and cursor.
    func resumeSession(_ sessionID: String) async -> (session: Session, messages: [Message], cursor: StreamCursor?)? {
        guard let runSession = sessions[sessionID] else { return nil }

        let metadata = await runSession.metadata
        let messages = await runSession.messages
        let seq = await runSession.currentSequence

        return (
            session: metadata,
            messages: messages,
            cursor: seq > 0 ? StreamCursor(sessionID: sessionID, sequence: seq) : nil
        )
    }

    /// Get a session by ID.
    func session(_ sessionID: String) -> ConversationRunSession? {
        sessions[sessionID]
    }

    /// Archive a session.
    func archiveSession(_ sessionID: String) async -> Session? {
        guard let runSession = sessions[sessionID] else { return nil }
        await runSession.archive()
        let metadata = await runSession.metadata
        try? store.saveSession(metadata)
        return metadata
    }

    /// Rename a session.
    func renameSession(_ sessionID: String, title: String) async -> Session? {
        guard let runSession = sessions[sessionID] else { return nil }
        await runSession.rename(to: title)
        let metadata = await runSession.metadata
        try? store.saveSession(metadata)
        return metadata
    }

    /// Delete a session permanently.
    func deleteSession(_ sessionID: String) async {
        if let runSession = sessions[sessionID] {
            await runSession.stop()
        }
        sessions.removeValue(forKey: sessionID)
        try? store.deleteSession(sessionID)
    }

    // MARK: - Messaging

    /// Send a user message to a session's agent.
    func sendMessage(_ sessionID: String, text: String, clientMessageID: String? = nil) async throws -> Message? {
        guard let runSession = sessions[sessionID] else { return nil }
        return try await runSession.sendMessage(text, clientMessageID: clientMessageID)
    }

    /// Respond to an approval request.
    func respondToApproval(
        sessionID: String,
        requestID: String,
        decision: ConversationDecision,
        note: String?
    ) async throws {
        guard let runSession = sessions[sessionID] else { return }
        try await runSession.respondToApproval(requestID: requestID, decision: decision, note: note)
    }

    /// Respond to a user input request.
    func respondToUserInput(
        sessionID: String,
        requestID: String,
        value: String
    ) async throws {
        guard let runSession = sessions[sessionID] else { return }
        try await runSession.respondToUserInput(requestID: requestID, value: value)
    }

    // MARK: - Persistence

    private func configurePersistence(for runSession: ConversationRunSession) async {
        await runSession.setPersistenceHandler { [store] session, messages in
            Task.detached {
                do {
                    try store.saveSession(session)
                    try store.saveMessages(messages, sessionID: session.id)
                } catch {
                    writeServerLog("failed to persist conversation session \(session.id): \(error)")
                }
            }
        }
    }
}
