//
//  ProcessProtocol.swift
//  devys
//
//  Protocol for CLI process wrappers (Codex, Claude Code, etc.)
//  NOT to be confused with Agent (our smart model).
//

import Foundation

// MARK: - Process Protocol

/// Protocol that CLI process wrappers must conform to.
/// This provides a unified interface for spawning and communicating with
/// Codex, Claude Code, and future CLI agents.
///
/// **Note:** This is the I/O layer. Agent (our model) uses these processes.
protocol ProcessProtocol: Actor {
    /// The workspace path this process operates in
    var workspacePath: String { get }
    
    /// Current connection state
    var state: ProcessState { get }
    
    /// Stream of events from the process
    var events: AsyncStream<ProcessEvent> { get }
    
    /// Start the CLI process
    func start() async throws
    
    /// Stop the CLI process
    func stop() async
    
    /// Send a message to the process
    func sendMessage(_ content: String, threadId: String?) async throws
    
    /// List all threads for this workspace
    func listThreads() async throws -> [ProcessThreadInfo]
    
    /// Resume a specific thread
    func resumeThread(_ id: String) async throws
    
    /// Archive a thread
    func archiveThread(_ id: String) async throws
    
    /// Respond to an approval request
    func respondToApproval(_ id: String, approved: Bool) async throws
}

// MARK: - Process State

/// Current state of a CLI process
enum ProcessState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "circle.dotted"
        case .connected: return "circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Process Events

/// Events emitted by a CLI process
enum ProcessEvent: Sendable {
    /// Process connected successfully
    case connected
    
    /// Process disconnected
    case disconnected
    
    /// New message from the process
    case message(ProcessMessage)
    
    /// Process is thinking/reasoning
    case reasoning(String)
    
    /// Process made a tool call
    case toolCall(ProcessToolCall)
    
    /// Tool call completed
    case toolResult(id: String, result: String, success: Bool)
    
    /// Process produced a diff
    case diff(ProcessFileDiff)
    
    /// Process needs approval for an action
    case approvalRequired(id: String, description: String, toolName: String)
    
    /// Usage statistics
    case usage(inputTokens: Int, outputTokens: Int)
    
    /// Error occurred
    case error(ProcessError)
    
    /// Thread list updated
    case threadsUpdated([ProcessThreadInfo])
    
    /// Turn completed (process finished responding)
    case turnComplete
}

// MARK: - Process Message

/// A message from the CLI process
struct ProcessMessage: Sendable {
    let id: String
    let role: String  // "user", "assistant", "system"
    let content: String
    let timestamp: Date
    
    init(id: String = UUID().uuidString, role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Process Tool Call

/// A tool call made by the CLI process
struct ProcessToolCall: Sendable {
    let id: String
    let name: String
    let arguments: [String: String]
    let timestamp: Date
    
    init(id: String = UUID().uuidString, name: String, arguments: [String: String] = [:], timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.timestamp = timestamp
    }
}

// MARK: - Process File Diff

/// A file diff from the CLI process
struct ProcessFileDiff: Sendable {
    let path: String
    let content: String  // Raw diff content
    let linesAdded: Int
    let linesRemoved: Int
    
    init(path: String, content: String, linesAdded: Int = 0, linesRemoved: Int = 0) {
        self.path = path
        self.content = content
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

// MARK: - Process Thread Info

/// Information about a thread from the CLI process
struct ProcessThreadInfo: Sendable, Identifiable {
    let id: String
    let title: String?
    let lastMessageAt: Date
    let messageCount: Int
    
    init(id: String, title: String? = nil, lastMessageAt: Date = Date(), messageCount: Int = 0) {
        self.id = id
        self.title = title
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
    }
}

// MARK: - Process Error

/// Errors that can occur with CLI processes
struct ProcessError: Error, Sendable {
    let code: String
    let message: String
    let recoverable: Bool
    
    init(code: String, message: String, recoverable: Bool = true) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
    }
    
    static let processNotStarted = ProcessError(code: "PROCESS_NOT_STARTED", message: "Process has not been started", recoverable: true)
    static let processTerminated = ProcessError(code: "PROCESS_TERMINATED", message: "Process terminated unexpectedly", recoverable: true)
    static let invalidResponse = ProcessError(code: "INVALID_RESPONSE", message: "Received invalid response from process", recoverable: true)
    static let timeout = ProcessError(code: "TIMEOUT", message: "Request timed out", recoverable: true)
}
