// AgentEvent.swift
// Unified events for UI consumption across harnesses.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Unified event type for both Claude Code and Codex harnesses.
///
/// This enum normalizes events from both CLI protocols into a single
/// stream that the UI can consume without knowing which harness is active.
public enum AgentEvent: Sendable {
    /// Streaming text delta from the agent.
    case messageDelta(String)

    /// Complete message content (final, non-streaming).
    case messageComplete(String)

    /// Turn/conversation round completed.
    case turnCompleted(turnId: String)

    /// Session started with rich initialization data.
    case sessionStarted(sessionId: String, model: String?)

    /// Session initialized with rich metadata (tools, commands, modes, version).
    case sessionInitialized(SessionInitInfo)

    /// Turn metrics (cost, duration, token usage).
    case turnMetrics(TurnMetrics)

    /// Approval required before proceeding.
    case approvalRequired(AgentApproval)

    /// Tool execution started.
    case toolStarted(id: String, name: String, input: String?, cwd: String? = nil, blockIndex: Int? = nil)

    /// Tool input streaming delta.
    case toolInputDelta(id: String?, blockIndex: Int?, delta: String)

    /// Tool output streaming.
    case toolOutput(id: String, output: String)

    /// Tool result with error metadata and structured output.
    case toolResult(id: String, output: String, isError: Bool, structuredOutput: String?)

    /// Tool metadata update.
    case toolMetadata(id: String, input: String?, cwd: String?, exitCode: Int?)

    /// Tool execution completed.
    case toolCompleted(id: String, status: String, exitCode: Int? = nil)

    /// Error occurred.
    case error(message: String)

    /// Reasoning/thinking delta (Claude with extended thinking).
    case reasoningDelta(String)

    /// Structured block added (diff, plan, todo, etc.).
    case blockAdded(ChatItemBlock)

    /// Structured block updated.
    case blockUpdated(ChatItemBlock)

    /// Raw event for debugging or unhandled types.
    case raw(source: String, type: String, payload: RawPayload?)
}

// MARK: - Session Init Info

/// Rich session initialization data available from both harnesses.
public struct SessionInitInfo: Sendable, Equatable {
    public let cliVersion: String?
    public let availableTools: [String]
    public let slashCommands: [String]
    public let permissionMode: String?

    public init(
        cliVersion: String? = nil,
        availableTools: [String] = [],
        slashCommands: [String] = [],
        permissionMode: String? = nil
    ) {
        self.cliVersion = cliVersion
        self.availableTools = availableTools
        self.slashCommands = slashCommands
        self.permissionMode = permissionMode
    }
}

// MARK: - Turn Metrics

/// Cost and performance metrics for a completed turn.
public struct TurnMetrics: Sendable, Equatable {
    public let durationMs: Int?
    public let totalCostUsd: Double?
    public let inputTokens: Int
    public let outputTokens: Int

    public init(
        durationMs: Int? = nil,
        totalCostUsd: Double? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.durationMs = durationMs
        self.totalCostUsd = totalCostUsd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - Session Mode

/// Permission/operating modes supported by agents.
public enum SessionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case `default` = "default"
    case acceptEdits = "acceptEdits"
    case plan = "plan"
    case dontAsk = "dontAsk"
    case bypassPermissions = "bypassPermissions"

    public var id: String { rawValue }
}

// MARK: - Approval Types

/// A request for user approval before executing an action.
public struct AgentApproval: Sendable, Identifiable, Equatable {
    public let id: String
    public let command: String?
    public let source: HarnessType
    public let toolUseId: String?
    public let toolName: String?
    public let input: String?
    public let cwd: String?
    public let permissionSuggestions: [String]
    public let blockedPath: String?
    public let decisionReason: String?

    public init(
        id: String,
        command: String?,
        source: HarnessType,
        toolUseId: String? = nil,
        toolName: String? = nil,
        input: String? = nil,
        cwd: String? = nil,
        permissionSuggestions: [String] = [],
        blockedPath: String? = nil,
        decisionReason: String? = nil
    ) {
        self.id = id
        self.command = command
        self.source = source
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.input = input
        self.cwd = cwd
        self.permissionSuggestions = permissionSuggestions
        self.blockedPath = blockedPath
        self.decisionReason = decisionReason
    }
}

/// User's decision on an approval request.
public enum AgentApprovalDecision: Sendable {
    case approve
    case deny
}

// MARK: - Raw Payload

/// Wrapper for untyped JSON payloads.
///
/// Marked `@unchecked Sendable` because the underlying dictionary is immutable
/// and contains only JSON-safe value types from `JSONSerialization`.
public struct RawPayload: @unchecked Sendable {
    public let value: [String: Any]

    public init(_ value: [String: Any]) {
        self.value = value
    }
}
