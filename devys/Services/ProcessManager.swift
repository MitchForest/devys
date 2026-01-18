//
//  ProcessManager.swift
//  devys
//
//  Manages CLI processes and observable UI state.
//  Views observe this directly - no intermediate Conversation layer.
//

import Foundation

/// Key for process lookup: (workspace path, agent type).
private struct ProcessKey: Hashable {
    let path: String
    let agentType: AgentType
}

/// Observable state for a single process connection.
/// Views observe this to render the conversation.
@MainActor
@Observable
final class ProcessSession: Identifiable {
    let id = UUID()
    let workspacePath: String
    let agentType: AgentType
    
    // MARK: - Observable State (views read, ProcessManager writes)
    
    var connectionState: ProcessState = .disconnected
    var messages: [Message] = []
    var threads: [Thread] = []
    var currentThreadId: String?
    var isProcessing: Bool = false
    var reasoningText: String = ""
    var pendingApproval: ApprovalRequest?
    var error: ProcessError?
    
    // MARK: - Internal
    
    fileprivate var process: (any ProcessProtocol)?
    fileprivate var eventTask: Task<Void, Never>?
    
    init(workspacePath: String, agentType: AgentType) {
        self.workspacePath = workspacePath
        self.agentType = agentType
    }
    
    // MARK: - Actions
    
    func send(_ content: String) async {
        guard let process, !content.isEmpty else { return }
        
        // Add user message immediately
        messages.append(Message(role: .user, content: content))
        isProcessing = true
        reasoningText = ""
        error = nil
        
        do {
            try await process.sendMessage(content, threadId: currentThreadId)
        } catch let err as ProcessError {
            isProcessing = false
            error = err
        } catch {
            isProcessing = false
            self.error = ProcessError(code: "SEND_FAILED", message: error.localizedDescription)
        }
    }
    
    func selectThread(_ thread: Thread) async {
        guard let process else { return }
        
        currentThreadId = thread.id
        messages = []
        isProcessing = true
        
        do {
            try await process.resumeThread(thread.id)
        } catch {
            self.error = ProcessError(code: "RESUME_FAILED", message: error.localizedDescription)
        }
        
        isProcessing = false
    }
    
    func approve() async {
        guard let process, let approval = pendingApproval else { return }
        pendingApproval = nil
        
        do {
            try await process.respondToApproval(approval.id, approved: true)
        } catch {
            self.error = ProcessError(code: "APPROVAL_FAILED", message: error.localizedDescription)
        }
    }
    
    func reject() async {
        guard let process, let approval = pendingApproval else { return }
        pendingApproval = nil
        
        do {
            try await process.respondToApproval(approval.id, approved: false)
        } catch {
            self.error = ProcessError(code: "APPROVAL_FAILED", message: error.localizedDescription)
        }
    }
    
    func dismissError() {
        error = nil
    }
    
    // MARK: - Event Handling
    
    fileprivate func handleEvent(_ event: ProcessEvent) {
        switch event {
        case .connected:
            connectionState = .connected
            error = nil
            
        case .disconnected:
            connectionState = .disconnected
            isProcessing = false
            
        case .message(let msg):
            let message = Message(
                id: msg.id,
                role: msg.role == "user" ? .user : .assistant,
                content: msg.content,
                timestamp: msg.timestamp
            )
            messages.append(message)
            
        case .reasoning(let text):
            reasoningText += text
            
        case .toolCall(let call):
            if var lastMessage = messages.last, lastMessage.role == .assistant {
                messages.removeLast()
                lastMessage.toolCalls.append(ToolCall(
                    id: call.id,
                    name: call.name,
                    arguments: call.arguments,
                    status: .running
                ))
                messages.append(lastMessage)
            }
            
        case .toolResult(let id, let result, let success):
            if var lastMessage = messages.last, lastMessage.role == .assistant {
                messages.removeLast()
                if let idx = lastMessage.toolCalls.firstIndex(where: { $0.id == id }) {
                    lastMessage.toolCalls[idx].result = result
                    lastMessage.toolCalls[idx].status = success ? .completed : .failed
                }
                messages.append(lastMessage)
            }
            
        case .diff(let diff):
            if var lastMessage = messages.last, lastMessage.role == .assistant {
                messages.removeLast()
                lastMessage.diffs.append(FileDiff(
                    path: diff.path,
                    content: diff.content,
                    linesAdded: diff.linesAdded,
                    linesRemoved: diff.linesRemoved
                ))
                messages.append(lastMessage)
            }
            
        case .approvalRequired(let id, let description, let toolName):
            pendingApproval = ApprovalRequest(id: id, description: description, toolName: toolName)
            
        case .error(let err):
            error = err
            isProcessing = false
            
        case .turnComplete:
            isProcessing = false
            reasoningText = ""
            
        case .threadsUpdated(let infos):
            threads = infos.map { Thread(
                id: $0.id,
                title: $0.title,
                cwd: workspacePath,
                lastMessageAt: $0.lastMessageAt,
                messageCount: $0.messageCount
            )}
            
        case .usage:
            break
        }
    }
}

/// Manages CLI processes and their observable sessions.
/// Inject via `.environment(processManager)` at the app level.
@MainActor
@Observable
final class ProcessManager {
    
    // MARK: - State
    
    private var processes: [ProcessKey: any ProcessProtocol] = [:]
    private var sessions: [ProcessKey: ProcessSession] = [:]
    
    // MARK: - Public API
    
    /// Get or create an observable session for a workspace + agent type.
    func session(workspacePath: String, agentType: AgentType) -> ProcessSession {
        let key = ProcessKey(path: workspacePath, agentType: agentType)
        
        if let existing = sessions[key] {
            return existing
        }
        
        let session = ProcessSession(workspacePath: workspacePath, agentType: agentType)
        sessions[key] = session
        return session
    }
    
    /// Start a session (connects to CLI process).
    func start(_ session: ProcessSession) async throws {
        let key = ProcessKey(path: session.workspacePath, agentType: session.agentType)
        
        // Get or create process
        let process: any ProcessProtocol
        if let existing = processes[key] {
            process = existing
        } else {
            process = createProcess(workspacePath: session.workspacePath, agentType: session.agentType)
            processes[key] = process
        }
        
        session.process = process
        session.connectionState = .connecting
        
        // Start the process
        try await process.start()
        session.connectionState = .connected
        
        // Start listening for events
        session.eventTask = Task { [weak session] in
            guard let session else { return }
            for await event in await process.events {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    session.handleEvent(event)
                }
            }
        }
        
        // Load threads
        await refreshThreads(session)
    }
    
    /// Stop a session.
    func stop(_ session: ProcessSession) async {
        session.eventTask?.cancel()
        session.eventTask = nil
        
        if let process = session.process {
            await process.stop()
        }
        
        session.process = nil
        session.connectionState = .disconnected
    }
    
    /// Refresh thread list for a session.
    func refreshThreads(_ session: ProcessSession) async {
        guard let process = session.process else { return }
        
        do {
            let infos = try await process.listThreads()
            session.threads = infos.map { Thread(
                id: $0.id,
                title: $0.title,
                cwd: session.workspacePath,
                lastMessageAt: $0.lastMessageAt,
                messageCount: $0.messageCount
            )}
        } catch {
            session.error = ProcessError(code: "LIST_FAILED", message: error.localizedDescription)
        }
    }
    
    /// Stop all processes.
    func stopAll() async {
        for session in sessions.values {
            await stop(session)
        }
        processes.removeAll()
        sessions.removeAll()
    }
    
    // MARK: - Internal
    
    private func createProcess(workspacePath: String, agentType: AgentType) -> any ProcessProtocol {
        switch agentType {
        case .codex:
            return CodexProcess(workspacePath: workspacePath)
        case .claudeCode:
            return ClaudeCodeProcess(workspacePath: workspacePath)
        }
    }
}
