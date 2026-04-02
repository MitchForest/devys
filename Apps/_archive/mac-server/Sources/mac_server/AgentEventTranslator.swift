import Agents
import ChatCore
import Foundation
import ServerProtocol

/// Translates `AgentEvent` (from CLI agent processes) into conversation protocol types.
///
/// The translator maintains message state — accumulating text deltas into complete messages,
/// tracking tool calls, and building `ConversationMessage` objects that the event log
/// can persist and clients can display.
actor AgentEventTranslator {
    private let sessionID: String
    private var currentAssistantMessage: MutableMessage?
    private var messageCounter: Int = 0

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    struct TranslationResult: Sendable {
        let events: [(type: ConversationEventType, payload: JSONValue?)]
        let updatedMessage: Message?
    }

    /// Translate an `AgentEvent` into zero or more conversation events.
    func translate(_ event: AgentEvent) -> TranslationResult {
        switch event {
        case .messageDelta(let text):
            return handleMessageDelta(text)

        case .messageComplete(let text):
            return handleMessageComplete(text)

        case .sessionStarted(let sid, let model):
            return handleSessionStarted(sessionID: sid, model: model)

        case .sessionInitialized(let info):
            return handleSessionInitialized(info)

        case .turnCompleted:
            return finishCurrentMessage(streamingState: .complete)

        case .turnMetrics(let metrics):
            return handleTurnMetrics(metrics)

        case .approvalRequired(let approval):
            return handleApprovalRequired(approval)

        case .toolStarted(let id, let name, let input, let cwd, _):
            return handleToolStarted(id: id, name: name, input: input, cwd: cwd)

        case .toolCompleted(let id, let status, let exitCode):
            return handleToolCompleted(id: id, status: status, exitCode: exitCode)

        case .toolOutput(let id, let output):
            return handleToolOutput(id: id, output: output)

        case .reasoningDelta(let text):
            let block = MessageBlock(
                kind: .reasoning,
                summary: text
            )
            return handleBlockEvent(block)

        case .blockAdded(let agentBlock):
            return handleAgentBlock(agentBlock)

        case .blockUpdated(let agentBlock):
            return handleAgentBlock(agentBlock)

        case .error(let message):
            let payload = encodePayload([
                "error": .string(message),
            ])
            return TranslationResult(
                events: [(.sessionStatus, payload)],
                updatedMessage: nil
            )

        default:
            return TranslationResult(events: [], updatedMessage: nil)
        }
    }

    /// Create a user message event (when user sends a message).
    func createUserMessage(text: String, explicitID: String? = nil) -> Message {
        if explicitID == nil {
            messageCounter += 1
        }
        return Message(
            id: explicitID ?? "msg-\(sessionID)-\(messageCounter)",
            sessionID: sessionID,
            role: .user,
            text: text,
            streamingState: .complete
        )
    }

    // MARK: - Private

    private func handleSessionStarted(sessionID: String, model: String?) -> TranslationResult {
        let payload = encodePayload([
            "sessionId": .string(sessionID),
            "model": model.map { .string($0) } ?? .null,
        ])
        return TranslationResult(
            events: [(.sessionStatus, payload)],
            updatedMessage: nil
        )
    }

    private func handleSessionInitialized(_ info: SessionInitInfo) -> TranslationResult {
        let payload = encodePayload([
            "cliVersion": info.cliVersion.map { .string($0) } ?? .null,
            "permissionMode": info.permissionMode.map { .string($0) } ?? .null,
        ])
        return TranslationResult(
            events: [(.sessionStatus, payload)],
            updatedMessage: nil
        )
    }

    private func handleTurnMetrics(_ metrics: TurnMetrics) -> TranslationResult {
        let payload = encodePayload([
            "durationMs": metrics.durationMs.map { .int($0) } ?? .null,
            "totalCostUsd": metrics.totalCostUsd.map { .double($0) } ?? .null,
            "inputTokens": .int(metrics.inputTokens),
            "outputTokens": .int(metrics.outputTokens),
        ])
        return TranslationResult(
            events: [(.sessionStatus, payload)],
            updatedMessage: nil
        )
    }

    private func handleApprovalRequired(_ approval: AgentApproval) -> TranslationResult {
        let block = MessageBlock(
            id: approval.id,
            kind: .toolCall,
            summary: approval.command ?? approval.toolName ?? "Approval required",
            payload: encodePayloadValue([
                "approvalRequestId": .string(approval.id),
                "command": approval.command.map { .string($0) } ?? .null,
                "toolName": approval.toolName.map { .string($0) } ?? .null,
                "input": approval.input.map { .string($0) } ?? .null,
                "cwd": approval.cwd.map { .string($0) } ?? .null,
            ])
        )
        return handleBlockEvent(block)
    }

    private func handleToolStarted(id: String, name: String, input: String?, cwd: String?) -> TranslationResult {
        let block = MessageBlock(
            id: id,
            kind: .toolCall,
            summary: name,
            payload: encodePayloadValue([
                "toolName": .string(name),
                "input": input.map { .string($0) } ?? .null,
                "cwd": cwd.map { .string($0) } ?? .null,
                "status": .string("running"),
            ])
        )
        return handleBlockEvent(block)
    }

    private func handleToolCompleted(id: String, status: String, exitCode: Int?) -> TranslationResult {
        let block = MessageBlock(
            id: id,
            kind: .toolCall,
            summary: nil,
            payload: encodePayloadValue([
                "status": .string(status),
                "exitCode": exitCode.map { .int($0) } ?? .null,
            ])
        )
        return handleBlockEvent(block)
    }

    private func handleToolOutput(id: String, output: String) -> TranslationResult {
        let block = MessageBlock(
            id: id,
            kind: .toolCall,
            summary: nil,
            payload: encodePayloadValue([
                "output": .string(output),
            ])
        )
        return handleBlockEvent(block)
    }

    private func handleMessageDelta(_ text: String) -> TranslationResult {
        let messageBuilder = currentOrNewAssistantMessage()
        messageBuilder.text += text

        let message = messageBuilder.toMessage(sessionID: sessionID, streamingState: .streaming)
        let payload = encodeMessage(message)
        return TranslationResult(
            events: [(.messageUpsert, payload)],
            updatedMessage: message
        )
    }

    private func handleMessageComplete(_ text: String) -> TranslationResult {
        let messageBuilder = currentOrNewAssistantMessage()
        messageBuilder.text = text

        let message = messageBuilder.toMessage(sessionID: sessionID, streamingState: .complete)
        let payload = encodeMessage(message)

        currentAssistantMessage = nil

        return TranslationResult(
            events: [(.messageUpsert, payload)],
            updatedMessage: message
        )
    }

    private func handleBlockEvent(_ block: MessageBlock) -> TranslationResult {
        let messageBuilder = currentOrNewAssistantMessage()
        if let idx = messageBuilder.blocks.firstIndex(where: { $0.id == block.id }) {
            messageBuilder.blocks[idx] = block
        } else {
            messageBuilder.blocks.append(block)
        }

        let message = messageBuilder.toMessage(sessionID: sessionID, streamingState: .streaming)
        let payload = encodeMessage(message)

        return TranslationResult(
            events: [(.messageBlockUpdated, payload)],
            updatedMessage: message
        )
    }

    private func handleAgentBlock(_ agentBlock: ChatItemBlock) -> TranslationResult {
        let block = MessageBlock(
            id: agentBlock.id,
            kind: mapBlockKind(agentBlock),
            summary: extractTitle(from: agentBlock),
            payload: nil
        )
        return handleBlockEvent(block)
    }

    private func extractTitle(from block: ChatItemBlock) -> String? {
        switch block {
        case .tool(let t): return t.name
        case .diff(let d): return d.title
        case .patch(let p): return p.title
        case .mcpTool(let m): return m.tool
        case .webSearch(let w): return w.query
        case .todoList(let t): return t.title
        case .plan(let p): return p.title
        case .userInput(let u): return u.title
        case .reasoning(let r): return String(r.text.prefix(80))
        case .systemStatus(let s): return s.title
        }
    }

    private func finishCurrentMessage(streamingState: StreamingState) -> TranslationResult {
        guard let msg = currentAssistantMessage else {
            return TranslationResult(events: [], updatedMessage: nil)
        }

        let message = msg.toMessage(sessionID: sessionID, streamingState: streamingState)
        let payload = encodeMessage(message)
        currentAssistantMessage = nil

        return TranslationResult(
            events: [(.messageUpsert, payload)],
            updatedMessage: message
        )
    }

    private func currentOrNewAssistantMessage() -> MutableMessage {
        if let currentAssistantMessage {
            return currentAssistantMessage
        }

        messageCounter += 1
        let next = MutableMessage(id: "msg-\(sessionID)-\(messageCounter)")
        currentAssistantMessage = next
        return next
    }

    private func mapBlockKind(_ block: ChatItemBlock) -> MessageBlockKind {
        switch block {
        case .tool: return .toolCall
        case .diff: return .diff
        case .patch: return .patch
        case .plan: return .plan
        case .todoList: return .todoList
        case .userInput: return .userInputRequest
        case .reasoning: return .reasoning
        case .systemStatus: return .systemStatus
        default: return .toolCall
        }
    }

    // MARK: - Encoding Helpers

    private func encodePayload(_ dict: [String: JSONValue]) -> JSONValue {
        .object(dict.mapValues { $0 })
    }

    private func encodePayloadValue(_ dict: [String: Payload]) -> Payload {
        .object(dict)
    }

    private func encodeMessage(_ message: Message) -> JSONValue? {
        guard let data = try? ServerJSONCoding.makeEncoder().encode(message),
              let json = try? ServerJSONCoding.makeDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return .object(["message": json])
    }
}

// MARK: - Mutable Message Builder

private final class MutableMessage: @unchecked Sendable {
    let id: String
    var text: String = ""
    var blocks: [MessageBlock] = []
    let timestamp: Date = .now

    init(id: String) {
        self.id = id
    }

    func toMessage(sessionID: String, streamingState: StreamingState) -> Message {
        Message(
            id: id,
            sessionID: sessionID,
            role: .assistant,
            text: text,
            blocks: blocks,
            streamingState: streamingState,
            timestamp: timestamp
        )
    }
}
