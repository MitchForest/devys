// ClaudeCodeEvent.swift
// NDJSON event parsing for Claude Code stream-json output.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Events from Claude Code CLI stream-json output.
///
/// Claude Code outputs NDJSON (one JSON object per line) with these event types:
/// - `system` (subtype: init) - Session started
/// - `stream_event` - Streaming content delta
/// - `assistant` - Complete assistant message
/// - `user` - Tool results
/// - `permission_request` - Approval needed
/// - `result` - Turn complete
/// - `error` - Error occurred
enum ClaudeCodeEvent: Sendable {
    case sessionStarted(sessionId: String, model: String?, initInfo: ClaudeSessionInitInfo?)
    case messageDelta(text: String)
    case messageComplete(text: String)
    case toolUse(id: String, name: String, input: String?)
    case toolResult(id: String, output: String, isError: Bool, structuredOutput: String?)
    case contentBlockStart(index: Int, blockType: String, id: String?, name: String?, input: String?)
    case contentBlockDelta(index: Int, deltaType: String, text: String?)
    case contentBlockStop(index: Int, blockType: String?)
    case reasoningText(text: String)
    case permissionRequest(ClaudePermissionRequest)
    case askUserQuestion(id: String, title: String, questions: [UserQuestion])
    case result(subtype: String, metrics: ClaudeTurnMetrics?)
    case error(message: String)
    case unknown(type: String, payload: RawPayload?)
}

extension ClaudeCodeEvent {
    // MARK: - Parsing

    static func parseEvents(from json: [String: Any]) -> [ClaudeCodeEvent] {
        guard let type = json["type"] as? String else {
            return [.unknown(type: "unknown", payload: RawPayload(json))]
        }

        switch type {
        case "system":
            return parseSystemEvent(json, type: type)
        case "stream_event":
            return parseStreamEventContainer(json, type: type)
        case "assistant":
            return parseAssistantEvent(json, type: type)
        case "user":
            return parseUserEvent(json, type: type)
        case "permission_request":
            return parsePermissionRequest(json)
        case "control_request":
            return parseControlRequest(json)
        case "result":
            return parseResultEvent(json)
        case "error":
            return parseErrorEvent(json)
        default:
            return [.unknown(type: type, payload: RawPayload(json))]
        }
    }

    private static func parseSystemEvent(_ json: [String: Any], type: String) -> [ClaudeCodeEvent] {
        if let subtype = json["subtype"] as? String, subtype == "init" {
            let sessionId = json["session_id"] as? String ?? ""
            let model = json["model"] as? String
            let initInfo = ClaudeSessionInitInfo(
                cliVersion: json["claude_code_version"] as? String,
                availableTools: json["tools"] as? [String] ?? [],
                slashCommands: json["slash_commands"] as? [String] ?? [],
                permissionMode: json["permissionMode"] as? String
            )
            return [.sessionStarted(sessionId: sessionId, model: model, initInfo: initInfo)]
        }
        return [.unknown(type: type, payload: RawPayload(json))]
    }

    private static func parseStreamEventContainer(_ json: [String: Any], type: String) -> [ClaudeCodeEvent] {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String else {
            return [.unknown(type: type, payload: RawPayload(json))]
        }
        return parseStreamEvent(eventType: eventType, event: event)
    }

    private static func parseAssistantEvent(_ json: [String: Any], type: String) -> [ClaudeCodeEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] else {
            return [.unknown(type: type, payload: RawPayload(json))]
        }
        return parseContentItems(content)
    }

    private static func parseUserEvent(_ json: [String: Any], type: String) -> [ClaudeCodeEvent] {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] else {
            return [.unknown(type: type, payload: RawPayload(json))]
        }
        return parseToolResults(content)
    }

    private static func parsePermissionRequest(_ json: [String: Any]) -> [ClaudeCodeEvent] {
        let requestId = json["request_id"] as? String ?? ""
        let command = json["command"] as? String
        let request = ClaudePermissionRequest(
            id: requestId,
            toolName: nil,
            command: command,
            input: nil,
            suggestions: [],
            blockedPath: nil,
            decisionReason: nil,
            toolUseId: nil
        )
        return [.permissionRequest(request)]
    }

    private static func parseControlRequest(_ json: [String: Any]) -> [ClaudeCodeEvent] {
        // Permission prompt from Claude Code CLI
        // Format: {"type":"control_request","request_id":"...","request":{"subtype":"can_use_tool","tool_name":"Bash",...}}
        let requestId = json["request_id"] as? String ?? ""
        guard let request = json["request"] as? [String: Any] else {
            return [.unknown(type: "control_request", payload: RawPayload(json))]
        }

        let subtype = request["subtype"] as? String ?? "unknown"
        if subtype == "can_use_tool" {
            let toolName = request["tool_name"] as? String
            let input = stringValue(request["input"])
            let command = parseCommand(from: request)
            let suggestions = parseSuggestions(request["permission_suggestions"])
            let blockedPath = request["blocked_path"] as? String
            let decisionReason = request["decision_reason"] as? String
            let toolUseId = request["tool_use_id"] as? String
            let permission = ClaudePermissionRequest(
                id: requestId,
                toolName: toolName,
                command: command,
                input: input,
                suggestions: suggestions,
                blockedPath: blockedPath,
                decisionReason: decisionReason,
                toolUseId: toolUseId
            )
            return [.permissionRequest(permission)]
        }

        if subtype == "ask_user_question" {
            let title = request["title"] as? String ?? "User Input"
            let questions = parseUserQuestions(request["questions"])
            return [.askUserQuestion(id: requestId, title: title, questions: questions)]
        }

        return [.unknown(type: "control_request:\(subtype)", payload: RawPayload(request))]
    }

    private static func parseResultEvent(_ json: [String: Any]) -> [ClaudeCodeEvent] {
        let subtype = json["subtype"] as? String ?? "unknown"
        let metrics = ClaudeTurnMetrics(
            durationMs: json["duration_ms"] as? Int,
            totalCostUsd: json["total_cost_usd"] as? Double
        )
        return [.result(subtype: subtype, metrics: metrics)]
    }

    private static func parseErrorEvent(_ json: [String: Any]) -> [ClaudeCodeEvent] {
        let message = json["message"] as? String ?? "Unknown error"
        return [.error(message: message)]
    }

    private static func parseContentItems(_ content: Any) -> [ClaudeCodeEvent] {
        guard let items = content as? [[String: Any]] else {
            if let text = content as? String, !text.isEmpty {
                return [.messageComplete(text: text)]
            }
            return []
        }

        var events: [ClaudeCodeEvent] = []
        var textChunks: [String] = []

        for item in items {
            guard let itemType = item["type"] as? String else { continue }
            switch itemType {
            case "text":
                if let text = item["text"] as? String, !text.isEmpty {
                    textChunks.append(text)
                }
            case "tool_use":
                let id = item["id"] as? String ?? UUID().uuidString
                let name = item["name"] as? String ?? "tool"
                let input = stringValue(item["input"])
                events.append(.toolUse(id: id, name: name, input: input))
            case "thinking":
                if let text = item["text"] as? String, !text.isEmpty {
                    events.append(.reasoningText(text: text))
                }
            default:
                events.append(.unknown(type: itemType, payload: RawPayload(item)))
            }
        }

        if !textChunks.isEmpty {
            events.insert(.messageComplete(text: textChunks.joined()), at: 0)
        }

        return events
    }

    private static func parseToolResults(_ content: Any) -> [ClaudeCodeEvent] {
        guard let items = content as? [[String: Any]] else {
            return []
        }

        var events: [ClaudeCodeEvent] = []

        for item in items {
            guard let itemType = item["type"] as? String, itemType == "tool_result" else { continue }
            let id = item["tool_use_id"] as? String ?? UUID().uuidString
            let output = stringValue(item["content"]) ?? ""
            let isError = item["is_error"] as? Bool ?? false
            let structured = stringValue(item["structuredContent"])
            events.append(.toolResult(id: id, output: output, isError: isError, structuredOutput: structured))
        }

        return events
    }

    static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    private static func parseStreamEvent(eventType: String, event: [String: Any]) -> [ClaudeCodeEvent] {
        switch eventType {
        case "content_block_start":
            let index = event["index"] as? Int ?? 0
            let block = event["content_block"] as? [String: Any] ?? [:]
            let blockType = block["type"] as? String ?? "unknown"
            let id = block["id"] as? String
            let name = block["name"] as? String
            let input = stringValue(block["input"])
            return [.contentBlockStart(index: index, blockType: blockType, id: id, name: name, input: input)]
        case "content_block_delta":
            let index = event["index"] as? Int ?? 0
            guard let delta = event["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else {
                return []
            }
            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                return [.messageDelta(text: text)]
            }
            if deltaType == "thinking_delta", let text = delta["text"] as? String, !text.isEmpty {
                return [.reasoningText(text: text)]
            }
            if deltaType == "input_json_delta" {
                let text = delta["partial_json"] as? String
                return [.contentBlockDelta(index: index, deltaType: deltaType, text: text)]
            }
            return []
        case "content_block_stop":
            let index = event["index"] as? Int ?? 0
            let block = event["content_block"] as? [String: Any]
            let blockType = block?["type"] as? String
            return [.contentBlockStop(index: index, blockType: blockType)]
        default:
            return []
        }
    }

}

extension ClaudeCodeEvent {
    // MARK: - Conversion

    /// Returns multiple AgentEvents when a single CLI event carries multiple pieces of data.
    /// For example, sessionStarted with initInfo emits both sessionStarted and sessionInitialized.
    func toAgentEvents() -> [AgentEvent] {
        switch self {
        case .sessionStarted(let sessionId, let model, let initInfo):
            var events: [AgentEvent] = [.sessionStarted(sessionId: sessionId, model: model)]
            if let info = initInfo {
                events.append(.sessionInitialized(SessionInitInfo(
                    cliVersion: info.cliVersion,
                    availableTools: info.availableTools,
                    slashCommands: info.slashCommands,
                    permissionMode: info.permissionMode
                )))
            }
            return events
        case .result(let subtype, let metrics):
            var events: [AgentEvent] = []
            if subtype == "success" || subtype == "error_during_execution"
                || subtype == "error_max_turns" || subtype == "error_max_budget_usd" {
                events.append(.turnCompleted(turnId: ""))
            } else {
                events.append(.raw(source: "claude-code", type: "result:\(subtype)", payload: nil))
            }
            if let m = metrics {
                events.append(.turnMetrics(TurnMetrics(
                    durationMs: m.durationMs,
                    totalCostUsd: m.totalCostUsd
                )))
            }
            return events
        default:
            return [toAgentEvent()]
        }
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    func toAgentEvent() -> AgentEvent {
        switch self {
        case .messageDelta(let text):
            return .messageDelta(text)
        case .messageComplete(let text):
            return .messageComplete(text)
        case .sessionStarted(let sessionId, let model, _):
            return .sessionStarted(sessionId: sessionId, model: model)
        case .toolUse(let id, let name, let input):
            return .toolStarted(id: id, name: name, input: input, cwd: nil, blockIndex: nil)
        case .toolResult(let id, let output, let isError, let structuredOutput):
            return .toolResult(id: id, output: output, isError: isError, structuredOutput: structuredOutput)
        case .contentBlockStart(let index, let blockType, let id, let name, let input):
            if blockType == "tool_use" {
                return .toolStarted(
                    id: id ?? "block_\(index)",
                    name: name ?? "tool",
                    input: input,
                    cwd: nil,
                    blockIndex: index
                )
            }
            return .raw(source: "claude-code", type: "content_block_start:\(blockType)", payload: nil)
        case .contentBlockDelta(let index, let deltaType, let text):
            if deltaType == "input_json_delta" {
                return .toolInputDelta(id: nil, blockIndex: index, delta: text ?? "")
            }
            return .raw(source: "claude-code", type: "content_block_delta:\(deltaType)", payload: nil)
        case .contentBlockStop:
            return .raw(source: "claude-code", type: "content_block_stop", payload: nil)
        case .reasoningText(let text):
            return .reasoningDelta(text)
        case .permissionRequest(let request):
            return .approvalRequired(
                AgentApproval(
                    id: request.id,
                    command: request.command,
                    source: .claudeCode,
                    toolUseId: request.toolUseId,
                    toolName: request.toolName,
                    input: request.input,
                    cwd: nil,
                    permissionSuggestions: request.suggestions,
                    blockedPath: request.blockedPath,
                    decisionReason: request.decisionReason
                )
            )
        case .askUserQuestion(let id, let title, let questions):
            return .blockAdded(
                .userInput(
                    UserInputBlock(
                        id: id,
                        title: title,
                        questions: questions,
                        answers: [],
                        status: .pending
                    )
                )
            )
        case .result(let subtype, _):
            if subtype == "success" || subtype == "error_during_execution" {
                return .turnCompleted(turnId: "")
            }
            if subtype == "error_max_turns" || subtype == "error_max_budget_usd" {
                return .turnCompleted(turnId: "")
            }
            return .raw(source: "claude-code", type: "result:\(subtype)", payload: nil)
        case .error(let message):
            return .error(message: message)
        case .unknown(let type, let payload):
            return .raw(source: "claude-code", type: type, payload: payload)
        }
    }
    // swiftlint:enable function_body_length cyclomatic_complexity
}

// MARK: - Support Types

/// Rich session initialization data from Claude Code's system.init event.
struct ClaudeSessionInitInfo: Sendable, Equatable {
    let cliVersion: String?
    let availableTools: [String]
    let slashCommands: [String]
    let permissionMode: String?
}

/// Metrics from a completed turn.
struct ClaudeTurnMetrics: Sendable, Equatable {
    let durationMs: Int?
    let totalCostUsd: Double?
}

struct ClaudePermissionRequest: Sendable, Equatable {
    let id: String
    let toolName: String?
    let command: String?
    let input: String?
    let suggestions: [String]
    let blockedPath: String?
    let decisionReason: String?
    let toolUseId: String?
}

private func parseCommand(from request: [String: Any]) -> String? {
    guard let input = request["input"] as? [String: Any] else { return nil }
    return input["command"] as? String
}

private func parseSuggestions(_ value: Any?) -> [String] {
    guard let raw = value as? [[String: Any]] else { return [] }
    return raw.compactMap { item in
        if let description = item["description"] as? String { return description }
        if let rule = item["rule"] as? String { return rule }
        return ClaudeCodeEvent.stringValue(item)
    }
}

private func parseUserQuestions(_ value: Any?) -> [UserQuestion] {
    guard let raw = value as? [[String: Any]] else { return [] }
    return raw.map { item in
        let question = item["question"] as? String ?? ""
        let options = item["options"] as? [String] ?? []
        let allowFreeform = item["allowFreeform"] as? Bool ?? true
        return UserQuestion(question: question, options: options, allowFreeform: allowFreeform)
    }
}
