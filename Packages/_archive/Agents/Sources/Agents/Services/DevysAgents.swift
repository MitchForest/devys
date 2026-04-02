// Agents.swift
// Public API for the Devys Agents package.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Logging

/// DevysAgents provides a native Swift interface to the Codex and Claude Code CLIs.
///
/// ## Architecture
///
/// **Codex App Server** handles:
/// - Agent loop (reasoning, planning, execution)
/// - Built-in tools (bash, read, write, edit, grep, glob, web_search)
/// - Skills loading (SKILL.md files)
/// - Thread/Turn persistence
/// - Sandboxing and approvals
///
/// **Claude Code** handles:
/// - Agent loop (reasoning, planning, execution)
/// - Built-in tools (bash, read, write, edit, grep, glob, web_search)
/// - Stream JSON I/O over stdio
/// - Session resume
///
/// ## Usage
///
/// ```swift
/// let agent = await DevysAgent(harnessType: .codex, cwd: "/path/to/project")
///
/// try await agent.start()
///
/// let thread = try await agent.startThread(cwd: "/path/to/project")
///
/// let turnId = try await agent.send("Fix the auth bug", to: thread.id, cwd: "/path/to/project")
///
/// for await event in await agent.events {
///     switch event {
///     case .messageDelta(let text):
///         logger.info(text)
///     case .approvalRequired(let request):
///         try await agent.respondToApproval(request, decision: .approve)
///     case .turnCompleted:
///         break
///     default:
///         break
///     }
/// }
/// ```
@MainActor
public final class DevysAgent {

    // MARK: - Components

    /// The active harness (Codex or Claude Code).
    let harness: ActiveHarness

    /// Selected model for this agent.
    public let model: LLMModel

    /// Working directory for the agent session.
    public let cwd: String
    
    private let logger = Logger(label: "devys.agent")
    
    // MARK: - Event Stream (created ONCE at init)
    
    /// Stream of unified agent events.
    /// 
    /// **Important:** This stream is created once at initialization and should only
    /// be iterated by a single consumer. Multiple consumers will split events.
    public let events: AsyncStream<AgentEvent>
    
    /// Continuation for yielding events to the stream.
    private let eventContinuation: AsyncStream<AgentEvent>.Continuation
    
    /// Task that forwards events from the harness to our unified stream.
    private var eventForwardingTask: Task<Void, Never>?

    /// Current state of the Codex client (Codex harness only).
    var codexState: CodexClient.State? {
        get async {
            switch harness {
            case .codex(let client):
                return await client.state
            case .claudeCode:
                return nil
            }
        }
    }

    // MARK: - Initialization

    /// Creates a new DevysAgent.
    public init(
        harnessType: HarnessType,
        cwd: String,
        model: LLMModel? = nil
    ) async {
        self.model = model ?? harnessType.defaultModel
        self.cwd = cwd

        switch harnessType {
        case .codex:
            self.harness = .codex(CodexClient())
        case .claudeCode:
            self.harness = .claudeCode(ClaudeCodeClient())
        }
        
        // Create unified event stream ONCE at initialization
        var continuation: AsyncStream<AgentEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.eventContinuation = continuation
        
        logger.info("DevysAgent initialized - harness: \(harnessType), model: \(self.model.rawValue), cwd: \(cwd)")
    }
    
    /// Starts forwarding events from the harness to the unified event stream.
    /// Must be called after the harness is started.
    private func startEventForwarding() {
        logger.info("Starting event forwarding task...")
        
        eventForwardingTask = Task { [weak self] in
            guard let self = self else { return }
            
            await self.forwardEvents()
        }
    }
    
    /// Forwards events from the active harness to the unified stream.
    /// Runs in a detached context to avoid MainActor contention.
    private func forwardEvents() async {
        logger.debug("forwardEvents() started")
        
        switch harness {
        case .codex(let client):
            var count = 0
            for await event in client.events {
                count += 1
                // Use toAgentEvents() to handle multi-event expansions (token metrics)
                let agentEvents = event.toAgentEvents()
                for agentEvent in agentEvents {
                    if count % 10 == 1 {
                        logger.debug("Forwarding Codex event #\(count): \(String(describing: agentEvent).prefix(80))")
                    }
                    eventContinuation.yield(agentEvent)
                }
            }
            logger.info("Codex event forwarding completed - forwarded \(count) events")
            
        case .claudeCode(let client):
            var count = 0
            for await event in client.events {
                count += 1
                // Use toAgentEvents() to handle multi-event expansions (sessionInitialized, turnMetrics)
                let agentEvents = event.toAgentEvents()
                for agentEvent in agentEvents {
                    if count % 10 == 1 {
                        logger.debug("Forwarding Claude event #\(count): \(String(describing: agentEvent).prefix(80))")
                    }
                    eventContinuation.yield(agentEvent)
                }
            }
            logger.info("Claude event forwarding completed - forwarded \(count) events")
        }
        
        eventContinuation.finish()
    }

    public var harnessType: HarnessType { harness.type }

    // MARK: - Lifecycle

    /// Starts the active harness.
    public func start() async throws {
        logger.info("DevysAgent.start() called (default)")
        try await start(permissionMode: .default, resumeSessionId: nil)
    }

    func start(
        permissionMode: ClaudeCodeClient.PermissionMode = .default,
        resumeSessionId: String? = nil
    ) async throws {
        logger.info("DevysAgent.start() - permissionMode: \(permissionMode), resumeSessionId: \(resumeSessionId ?? "nil")")
        
        switch harness {
        case .codex(let client):
            logger.info("Starting Codex client...")
            try await client.start()
            logger.info("Codex client started")
        case .claudeCode(let client):
            logger.info("Starting Claude Code client...")
            try await client.start(
                cwd: cwd,
                model: model,
                permissionMode: permissionMode,
                resumeSessionId: resumeSessionId
            )
            logger.info("Claude Code client started")
        }
        
        // Start forwarding events from harness to unified stream
        startEventForwarding()
    }

    /// Stops the agent.
    public func stop() async {
        logger.info("DevysAgent.stop() called")
        
        // Cancel event forwarding first
        eventForwardingTask?.cancel()
        eventForwardingTask = nil
        
        // Stop the harness
        await harness.stop()
        
        // Finish the event stream
        eventContinuation.finish()
        
        logger.info("DevysAgent stopped")
    }

    // MARK: - Codex Thread Management

    public func startThread(
        cwd: String,
        model: String? = nil,
        configuration: AgentConfiguration = .default
    ) async throws -> CodexThread {
        logger.info("DevysAgent.startThread() - cwd: \(cwd)")
        guard case .codex(let client) = harness else {
            logger.error("startThread() failed - not a Codex harness")
            throw DevysAgentError.unsupportedHarness
        }
        let thread = try await client.startThread(cwd: cwd, model: model, configuration: configuration)
        logger.info("Thread started: \(thread.id)")
        return thread
    }

    public func resumeThread(id: String) async throws -> CodexThread {
        logger.info("DevysAgent.resumeThread() - id: \(id)")
        guard case .codex(let client) = harness else {
            logger.error("resumeThread() failed - not a Codex harness")
            throw DevysAgentError.unsupportedHarness
        }
        let thread = try await client.resumeThread(id: id)
        logger.info("Thread resumed: \(thread.id)")
        return thread
    }

    // MARK: - Conversation

    public func send(
        _ message: String,
        to threadId: String,
        cwd: String,
        model: String? = nil,
        configuration: AgentConfiguration = .default
    ) async throws -> String {
        logger.info("DevysAgent.send() - threadId: \(threadId), message length: \(message.count)")
        guard case .codex(let client) = harness else {
            logger.error("send() failed - not a Codex harness")
            throw DevysAgentError.unsupportedHarness
        }
        let turnId = try await client.startTurn(
            threadId: threadId,
            prompt: message,
            cwd: cwd,
            model: model,
            configuration: configuration
        )
        logger.info("Turn started: \(turnId)")
        return turnId
    }

    public func query(_ message: String) async throws {
        logger.info("DevysAgent.query() - message length: \(message.count)")
        guard case .claudeCode(let client) = harness else {
            logger.error("query() failed - not a Claude Code harness")
            throw DevysAgentError.unsupportedHarness
        }
        try await client.query(prompt: message)
        logger.info("Query sent successfully")
    }

    // MARK: - Approvals

    public func respondToApproval(
        _ request: AgentApproval,
        decision: AgentApprovalDecision,
        forSession: Bool = false
    ) async throws {
        switch harness {
        case .codex(let client):
            guard let requestId = Int(request.id) else {
                throw DevysAgentError.invalidApprovalId
            }
            let codexDecision: ApprovalDecision = (decision == .approve) ? .accept : .decline
            try await client.respondToApproval(requestId: requestId, decision: codexDecision, forSession: forSession)
        case .claudeCode(let client):
            let claudeDecision: ClaudeApprovalDecision = (decision == .approve) ? .approve : .deny
            try await client.respondToApproval(requestId: request.id, decision: claudeDecision)
        }
    }

    public func respondToUserInput(
        requestId: String,
        answers: [String]
    ) async throws -> Bool {
        switch harness {
        case .codex(let client):
            do {
                try await client.respondToUserInput(requestId: requestId, answers: answers)
                return true
            } catch {
                logger.warning("Codex user input response failed: \(error)")
                return false
            }
        case .claudeCode(let client):
            try await client.respondToUserInput(requestId: requestId, answers: answers)
            return true
        }
    }

    public func listSkills(cwd: String) async throws -> CodexJSONArray {
        guard case .codex(let client) = harness else {
            throw DevysAgentError.unsupportedHarness
        }
        return try await client.listSkills(cwds: [cwd])
    }

    // MARK: - Harness Access

    var codex: CodexClient? {
        if case .codex(let client) = harness { return client }
        return nil
    }

}

// MARK: - Errors

public enum DevysAgentError: Error, LocalizedError {
    case unsupportedHarness
    case invalidApprovalId

    public var errorDescription: String? {
        switch self {
        case .unsupportedHarness:
            return "This operation is not supported by the active harness."
        case .invalidApprovalId:
            return "Approval request ID is invalid for the active harness."
        }
    }
}
