// CodexEvent.swift
// JSON-RPC event parsing for Codex App Server.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

// swiftlint:disable type_body_length
/// Events from Codex App Server.
///
/// Codex uses JSON-RPC notifications with these methods:
/// - `thread/started`, `turn/started`, `turn/completed`
/// - `item/started`, `item/completed`
/// - `item/agentMessage/delta` - Streaming text
/// - `item/commandExecution/outputDelta` - Command output
/// - `item/commandExecution/requestApproval` - Approval needed
/// - `item/reasoning/*` - Thinking/reasoning events
enum CodexEvent: Sendable {
    case threadStarted(threadId: String)
    case turnStarted(turnId: String)
    case turnCompleted(turnId: String)
    case turnError(message: String, willRetry: Bool)
    case itemStarted(itemId: String, type: String, payload: RawPayload?)
    case itemCompleted(itemId: String, status: String, payload: RawPayload?)
    case agentMessageDelta(text: String)
    case agentMessage(id: String, content: String)
    case reasoningSummaryDelta(itemId: String, text: String)
    case reasoningTextDelta(itemId: String, text: String)
    case commandOutputDelta(itemId: String, text: String)
    case approvalRequired(ApprovalRequest)
    case userInputRequest(itemId: String, title: String, questions: [UserQuestion])
    case toolExecution(name: String, status: String)
    case execCommandBegin(itemId: String, command: String?, cwd: String?)
    case execCommandEnd(itemId: String, exitCode: Int?)
    case tokenCount(inputTokens: Int, outputTokens: Int, reasoningTokens: Int)
    case tokenUsageUpdated(threadId: String, inputTokens: Int, outputTokens: Int)
    case mcpStartupUpdate(server: String, state: String)
    case mcpStartupComplete(ready: [String], failed: [String])
    case warning(message: String)
    case unknown(method: String, params: RawPayload?)

    // MARK: - Parsing

    static func parse(method: String, params: [String: Any], requestId: Int?) -> CodexEvent {
        if let parser = parsers[method] {
            return parser(method, params, requestId)
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    // MARK: - Helpers

    /// Returns true if the string is a simple integer (like "1", "2").
    /// These are turn IDs, not item IDs. Real item IDs have prefixes like "rs_", "msg_", "cmd_".
    private static func isSimpleInteger(_ string: String) -> Bool {
        guard !string.isEmpty else { return false }
        return Int(string) != nil
    }

    private typealias Parser = @Sendable (_ method: String, _ params: [String: Any], _ requestId: Int?) -> CodexEvent

    private static let parsers: [String: Parser] = [
        // Thread events
        "thread/started": parseThreadStarted,

        // Turn events
        "turn/started": parseTurnStarted,
        "turn/completed": parseTurnCompleted,
        "codex/event/task_complete": parseTurnCompleted,
        "codex/event/task_started": parseTaskStarted,

        // Item events
        "item/started": parseItemStarted,
        "codex/event/item_started": parseIgnored, // duplicate of item/started
        "item/completed": parseItemCompleted,
        "codex/event/item_completed": parseIgnored, // duplicate of item/completed

        // Agent message events
        "item/agentMessage/delta": parseAgentMessageDelta,
        "codex/event/agent_message_delta": parseIgnored,
        "codex/event/agent_message_content_delta": parseIgnored,
        "codex/event/agent_message": parseAgentMessage,

        // Reasoning events
        "item/reasoning/summaryTextDelta": parseReasoningSummaryDelta,
        "item/reasoning/summaryPartAdded": parseIgnored, // section marker
        "item/reasoning/textDelta": parseReasoningTextDelta,
        "codex/event/reasoning_content_delta": parseCodexReasoningDelta,
        "codex/event/agent_reasoning_delta": parseIgnored, // duplicate of reasoning deltas
        "codex/event/agent_reasoning": parseIgnored, // complete reasoning (we stream it)
        "codex/event/agent_reasoning_section_break": parseIgnored, // cosmetic marker

        // Command execution events
        "codex/event/exec_command_begin": parseExecCommandBegin,
        "codex/event/exec_command_end": parseExecCommandEnd,
        "item/commandExecution/outputDelta": parseCommandOutputDelta,

        // Error events
        "error": parseError,

        // Approval events
        "item/commandExecution/requestApproval": parseApprovalRequired,
        "item/fileChange/requestApproval": parseFileChangeApprovalRequired,
        "codex/event/command_approval_request": parseApprovalRequired,

        // User input request
        "item/tool/requestUserInput": parseUserInputRequest,

        // Tool events
        "codex/event/tool_execution": parseToolExecution,

        // Token/usage events (extracted for cost tracking)
        "codex/event/token_count": parseTokenCount,
        "thread/tokenUsage/updated": parseTokenUsageUpdated,
        "account/rateLimits/updated": parseIgnored, // rate limits — future UI

        // MCP startup events
        "codex/event/mcp_startup_update": parseMCPStartupUpdate,
        "codex/event/mcp_startup_complete": parseMCPStartupComplete,

        // Misc events we intentionally ignore
        "codex/event/warning": parseWarning,
        "codex/event/user_message": parseIgnored, // echo of user input
    ]

    private static func parseThreadStarted(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        // Real output: {"method":"thread/started","params":{"thread":{"id":"..."}}}
        if let thread = params["thread"] as? [String: Any] {
            return .threadStarted(threadId: thread["id"] as? String ?? "")
        }
        return .threadStarted(threadId: params["threadId"] as? String ?? "")
    }

    private static func parseTurnStarted(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        if let turn = params["turn"] as? [String: Any] {
            return .turnStarted(turnId: turn["id"] as? String ?? "")
        }
        let turnId = params["turnId"] as? String ?? params["turn_id"] as? String ?? ""
        return .turnStarted(turnId: turnId)
    }

    private static func parseTurnCompleted(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        if let turn = params["turn"] as? [String: Any] {
            return .turnCompleted(turnId: turn["id"] as? String ?? "")
        }
        let turnId = params["turnId"] as? String ?? params["turn_id"] as? String ?? ""
        return .turnCompleted(turnId: turnId)
    }

    private static func parseTaskStarted(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        .turnStarted(turnId: params["taskId"] as? String ?? "")
    }

    private static func parseItemStarted(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        if let item = params["item"] as? [String: Any] {
            let itemId = item["id"] as? String ?? ""
            let itemType = item["type"] as? String ?? ""
            guard !itemId.isEmpty, !isSimpleInteger(itemId) else {
                return .unknown(method: method, params: RawPayload(params))
            }
            return .itemStarted(itemId: itemId, type: itemType, payload: RawPayload(item))
        }
        let itemId = params["itemId"] as? String ?? ""
        guard !itemId.isEmpty, !isSimpleInteger(itemId) else {
            return .unknown(method: method, params: RawPayload(params))
        }
        return .itemStarted(
            itemId: itemId,
            type: params["type"] as? String ?? "",
            payload: RawPayload(params)
        )
    }

    private static func parseItemCompleted(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let itemId: String
        var payload: RawPayload?
        if let item = params["item"] as? [String: Any] {
            itemId = item["id"] as? String ?? params["itemId"] as? String ?? ""
            payload = RawPayload(item)
        } else {
            itemId = params["itemId"] as? String ?? ""
            payload = RawPayload(params)
        }
        guard !itemId.isEmpty, !isSimpleInteger(itemId) else {
            return .unknown(method: method, params: RawPayload(params))
        }
        return .itemCompleted(
            itemId: itemId,
            status: params["status"] as? String ?? "completed",
            payload: payload
        )
    }

    private static func parseAgentMessageDelta(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        if let delta = params["delta"] as? String, !delta.isEmpty {
            return .agentMessageDelta(text: delta)
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseAgentMessage(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        if let msg = params["msg"] as? [String: Any],
           let message = msg["message"] {
            let id = "\(params["id"] ?? "")"
            return .agentMessage(id: id, content: "\(message)")
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseUserInputRequest(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let itemId = params["requestId"] as? String
            ?? params["request_id"] as? String
            ?? params["itemId"] as? String
            ?? params["item_id"] as? String
            ?? ""
        let title = params["title"] as? String ?? "User Input"
        let questions = parseUserQuestions(params["questions"])
        guard !itemId.isEmpty else {
            return .unknown(method: method, params: RawPayload(params))
        }
        return .userInputRequest(itemId: itemId, title: title, questions: questions)
    }

    private static func parseReasoningSummaryDelta(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let itemId = params["itemId"] as? String ?? params["item_id"] as? String ?? ""
        if let delta = params["delta"] as? String, !delta.isEmpty {
            return .reasoningSummaryDelta(itemId: itemId, text: delta)
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseReasoningTextDelta(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let itemId = params["itemId"] as? String ?? params["item_id"] as? String ?? ""
        if let delta = params["delta"] as? String, !delta.isEmpty {
            return .reasoningTextDelta(itemId: itemId, text: delta)
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseCommandOutputDelta(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let itemId = params["itemId"] as? String ?? params["item_id"] as? String ?? ""
        if let delta = params["delta"] as? String, !delta.isEmpty {
            return .commandOutputDelta(itemId: itemId, text: delta)
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseError(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        if let error = params["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            let willRetry = params["willRetry"] as? Bool ?? params["will_retry"] as? Bool ?? false
            return .turnError(message: message, willRetry: willRetry)
        }
        return .turnError(message: "Unknown error", willRetry: false)
    }

    private static func parseApprovalRequired(
        method: String,
        params: [String: Any],
        requestId: Int?
    ) -> CodexEvent {
        if let requestId {
            return .approvalRequired(ApprovalRequest(from: params, requestId: requestId, kind: .commandExecution))
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseFileChangeApprovalRequired(
        method: String,
        params: [String: Any],
        requestId: Int?
    ) -> CodexEvent {
        if let requestId {
            return .approvalRequired(ApprovalRequest(from: params, requestId: requestId, kind: .fileChange))
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseToolExecution(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        .toolExecution(
            name: params["name"] as? String ?? "",
            status: params["status"] as? String ?? ""
        )
    }

    private static func parseCodexReasoningDelta(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        // Format: {"method":"codex/event/reasoning_content_delta","params":{"id":"1","msg":{"delta":"..."}}}
        if let msg = params["msg"] as? [String: Any],
           let delta = msg["delta"] as? String, !delta.isEmpty {
            let itemId = msg["item_id"] as? String ?? ""
            return .reasoningTextDelta(itemId: itemId, text: delta)
        }
        return .unknown(method: method, params: RawPayload(params))
    }

    private static func parseExecCommandBegin(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        // Format: {"method":"codex/event/exec_command_begin","params":{"id":"1","msg":{...}}}
        let msg = params["msg"] as? [String: Any] ?? [:]
        let itemId = msg["item_id"] as? String ?? params["id"] as? String ?? ""
        let command = msg["command"] as? String
        let cwd = msg["cwd"] as? String
        return .execCommandBegin(itemId: itemId, command: command, cwd: cwd)
    }

    private static func parseExecCommandEnd(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let msg = params["msg"] as? [String: Any] ?? [:]
        let itemId = msg["item_id"] as? String ?? params["id"] as? String ?? ""
        let exitCode = msg["exit_code"] as? Int ?? msg["exitCode"] as? Int
        return .execCommandEnd(itemId: itemId, exitCode: exitCode)
    }

    private static func parseTokenCount(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let msg = params["msg"] as? [String: Any] ?? [:]
        let info = msg["info"] as? [String: Any]
        let usage = info?["total_token_usage"] as? [String: Any] ?? [:]
        return .tokenCount(
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            reasoningTokens: usage["reasoning_output_tokens"] as? Int ?? 0
        )
    }

    private static func parseTokenUsageUpdated(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let threadId = params["threadId"] as? String ?? ""
        let usage = params["tokenUsage"] as? [String: Any]
        let total = usage?["total"] as? [String: Any] ?? [:]
        return .tokenUsageUpdated(
            threadId: threadId,
            inputTokens: total["inputTokens"] as? Int ?? 0,
            outputTokens: total["outputTokens"] as? Int ?? 0
        )
    }

    private static func parseMCPStartupUpdate(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let msg = params["msg"] as? [String: Any] ?? [:]
        let server = msg["server"] as? String ?? ""
        let status = msg["status"] as? [String: Any] ?? [:]
        let state = status["state"] as? String ?? "unknown"
        return .mcpStartupUpdate(server: server, state: state)
    }

    private static func parseMCPStartupComplete(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let msg = params["msg"] as? [String: Any] ?? [:]
        let ready = msg["ready"] as? [String] ?? []
        let failed = msg["failed"] as? [String] ?? []
        return .mcpStartupComplete(ready: ready, failed: failed)
    }

    private static func parseWarning(
        _: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        let msg = params["msg"] as? [String: Any] ?? [:]
        let message = msg["message"] as? String ?? "Unknown warning"
        return .warning(message: message)
    }

    private static func parseIgnored(
        method: String,
        params: [String: Any],
        _: Int?
    ) -> CodexEvent {
        .unknown(method: method, params: RawPayload(params))
    }

}
// swiftlint:enable type_body_length
