// CodexEvent+Conversion.swift
// Conversion helpers for Codex events.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

extension CodexEvent {
    // MARK: - Conversion

    /// Returns multiple AgentEvents when a single event carries separate pieces of data.
    func toAgentEvents() -> [AgentEvent] {
        switch self {
        case .tokenCount(let inputTokens, let outputTokens, _):
            return [
                .turnMetrics(TurnMetrics(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                ))
            ]
        case .tokenUsageUpdated(_, let inputTokens, let outputTokens):
            return [
                .turnMetrics(TurnMetrics(
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                ))
            ]
        default:
            return [toAgentEvent()]
        }
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    func toAgentEvent() -> AgentEvent {
        switch self {
        case .agentMessageDelta(let text):
            return .messageDelta(text)
        case .agentMessage(_, let content):
            return .messageComplete(content)
        case .turnCompleted(let turnId):
            return .turnCompleted(turnId: turnId)
        case .approvalRequired(let request):
            let toolName: String?
            switch request.kind {
            case .fileChange:
                toolName = "File Change"
            case .commandExecution:
                toolName = "Command Execution"
            case .tool:
                toolName = "Tool"
            case .unknown:
                toolName = nil
            }
            return .approvalRequired(
                AgentApproval(
                    id: String(request.id),
                    command: request.command,
                    source: .codex,
                    toolUseId: request.itemId,
                    toolName: toolName,
                    input: nil,
                    cwd: request.cwd,
                    permissionSuggestions: [],
                    blockedPath: nil,
                    decisionReason: request.reason
                )
            )
        case .itemStarted(let itemId, let type, let payload):
            // Skip message-like items - they're not tools, they're content containers
            // agentMessage: The actual text comes via item/agentMessage/delta
            // userMessage: Echo of user input
            // reasoning: Thinking/planning text
            let lowercasedType = type.lowercased()
            if ["agentmessage", "usermessage", "reasoning"].contains(lowercasedType) {
                return .raw(source: "codex", type: "itemStarted:\(type)", payload: nil)
            }
            if let block = Self.blockFromCodexItem(type: type, payload: payload, itemId: itemId, status: "running") {
                return .blockAdded(block)
            }
            let input = Self.stringifyJSON(payload?.value["input"]) ?? payload?.value["command"] as? String
            let cwd = payload?.value["cwd"] as? String
            return .toolStarted(id: itemId, name: type, input: input, cwd: cwd, blockIndex: nil)
        case .itemCompleted(let itemId, let status, let payload):
            // Skip message-like items - same as itemStarted
            // We can detect these by their ID prefix: msg_ for messages, rs_ for reasoning
            if itemId.hasPrefix("msg_") || itemId.hasPrefix("rs_") {
                return .raw(source: "codex", type: "itemCompleted:\(itemId)", payload: nil)
            }
            if let block = Self.blockFromCodexItem(
                type: payload?.value["type"] as? String ?? "",
                payload: payload,
                itemId: itemId,
                status: status
            ) {
                return .blockUpdated(block)
            }
            if let message = payload?.value["content"] as? String {
                return .messageComplete(message)
            }
            let exitCode = payload?.value["exitCode"] as? Int ?? payload?.value["exit_code"] as? Int
            return .toolCompleted(id: itemId, status: status, exitCode: exitCode)
        case .commandOutputDelta(let itemId, let text):
            return .toolOutput(id: itemId, output: text)
        case .reasoningTextDelta(_, let text):
            return .reasoningDelta(text)
        case .reasoningSummaryDelta(_, let text):
            return .reasoningDelta(text)
        case .turnError(let message, _):
            return .error(message: message)
        case .userInputRequest(let itemId, let title, let questions):
            return .blockAdded(
                .userInput(
                    UserInputBlock(
                        id: itemId,
                        title: title,
                        questions: questions,
                        answers: [],
                        status: .pending
                    )
                )
            )
        case .execCommandBegin(let itemId, let command, let cwd):
            return .toolStarted(id: itemId, name: "commandExecution", input: command, cwd: cwd, blockIndex: nil)
        case .execCommandEnd(let itemId, let exitCode):
            return .toolCompleted(id: itemId, status: "completed", exitCode: exitCode)
        case .tokenCount, .tokenUsageUpdated:
            // Token data — future: surface in UI as cost indicator
            return .raw(source: "codex", type: "tokenUsage", payload: nil)
        case .mcpStartupUpdate(let server, let state):
            return .blockAdded(
                .systemStatus(
                    SystemStatusBlock(
                        title: "MCP: \(server)",
                        detail: state,
                        level: state == "ready" ? .info : .warning
                    )
                )
            )
        case .mcpStartupComplete(_, let failed):
            if !failed.isEmpty {
                return .blockAdded(
                    .systemStatus(
                        SystemStatusBlock(
                            title: "MCP Startup",
                            detail: "Failed: \(failed.joined(separator: ", "))",
                            level: .error
                        )
                    )
                )
            }
            // Silently succeed — don't clutter UI when everything works
            return .raw(source: "codex", type: "mcpStartupComplete", payload: nil)
        case .warning(let message):
            return .blockAdded(
                .systemStatus(
                    SystemStatusBlock(
                        title: "Warning",
                        detail: message,
                        level: .warning
                    )
                )
            )
        case .unknown(let method, let params):
            return .raw(source: "codex", type: method, payload: params)
        default:
            return .raw(source: "codex", type: "\(self)", payload: nil)
        }
    }
    // swiftlint:enable function_body_length cyclomatic_complexity
}

extension CodexEvent {
    // MARK: - Blocks + Helpers

    static func parseUserQuestions(_ value: Any?) -> [UserQuestion] {
        guard let raw = value as? [[String: Any]] else { return [] }
        return raw.map { item in
            let question = item["question"] as? String ?? ""
            let options = item["options"] as? [String] ?? []
            let allowFreeform = item["allowFreeform"] as? Bool ?? true
            return UserQuestion(question: question, options: options, allowFreeform: allowFreeform)
        }
    }

    // swiftlint:disable function_body_length
    private static func blockFromCodexItem(
        type: String,
        payload: RawPayload?,
        itemId: String,
        status: String
    ) -> ChatItemBlock? {
        let normalized = type.lowercased()
        let data = payload?.value ?? [:]

        switch normalized {
        case "filechange", "patch":
            let title = data["title"] as? String ?? "File Changes"
            let summary = data["summary"] as? String ?? data["description"] as? String
            let files = parsePatchFiles(data["files"] ?? data["changes"])
            let patchStatus: PatchBlock.PatchStatus
            switch status.lowercased() {
            case "completed":
                patchStatus = .completed
            case "failed", "error":
                patchStatus = .failed
            default:
                patchStatus = .running
            }
            return .patch(
                PatchBlock(
                    id: itemId,
                    title: title,
                    summary: summary,
                    files: files,
                    status: patchStatus
                )
            )
        case "mcptoolcall":
            let server = data["server"] as? String ?? data["serverName"] as? String ?? "mcp"
            let tool = data["tool"] as? String ?? data["toolName"] as? String ?? "tool"
            let input = stringifyJSON(data["input"]) ?? ""
            let output = stringifyJSON(data["output"]) ?? ""
            let isError = data["isError"] as? Bool ?? data["is_error"] as? Bool ?? false
            return .mcpTool(
                MCPToolBlock(id: itemId, server: server, tool: tool, input: input, output: output, isError: isError)
            )
        case "websearch", "web_search":
            let query = data["query"] as? String ?? data["search"] as? String ?? "Web Search"
            let summary = data["summary"] as? String ?? ""
            let statusValue = status == "completed" ? WebSearchBlock.WebSearchStatus.completed : .running
            return .webSearch(
                WebSearchBlock(id: itemId, query: query, status: statusValue, summary: summary)
            )
        case "todo-list", "todolist":
            let title = data["title"] as? String ?? "Todo List"
            let items = parseTodoItems(data["items"])
            return .todoList(TodoListBlock(id: itemId, title: title, items: items))
        case "planimplementation", "plan":
            let title = data["title"] as? String ?? "Plan"
            let steps = parsePlanSteps(data["steps"])
            let planStatus: PlanBlock.PlanStatus = status == "completed" ? .completed : .proposed
            return .plan(PlanBlock(id: itemId, title: title, steps: steps, status: planStatus))
        case "diff":
            let title = data["title"] as? String ?? "Diff"
            let diff = data["diff"] as? String ?? data["content"] as? String ?? ""
            if diff.isEmpty { return nil }
            return .diff(DiffBlock(id: itemId, title: title, diff: diff))
        default:
            return nil
        }
    }

    private static func parsePatchFiles(_ value: Any?) -> [PatchFileChange] {
        guard let raw = value as? [[String: Any]] else { return [] }
        return raw.map { item in
            let path = item["path"] as? String ?? item["file"] as? String ?? "Unknown"
            let status = item["status"] as? String ?? "modified"
            let additions = item["additions"] as? Int ?? 0
            let deletions = item["deletions"] as? Int ?? 0
            let diff = item["diff"] as? String
            return PatchFileChange(path: path, status: status, additions: additions, deletions: deletions, diff: diff)
        }
    }

    private static func parseTodoItems(_ value: Any?) -> [TodoItem] {
        guard let raw = value as? [[String: Any]] else { return [] }
        return raw.map { item in
            let text = item["text"] as? String ?? item["title"] as? String ?? ""
            let complete = item["completed"] as? Bool ?? item["done"] as? Bool ?? false
            return TodoItem(text: text, isComplete: complete)
        }
    }

    private static func parsePlanSteps(_ value: Any?) -> [PlanStep] {
        guard let raw = value as? [[String: Any]] else { return [] }
        return raw.map { item in
            let text = item["text"] as? String ?? item["title"] as? String ?? ""
            let complete = item["completed"] as? Bool ?? item["done"] as? Bool ?? false
            return PlanStep(text: text, isComplete: complete)
        }
    }

    private static func stringifyJSON(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }
    // swiftlint:enable function_body_length
}
