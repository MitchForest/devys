// CodexEventTests.swift
// Tests for Codex JSON-RPC event parsing.
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
@testable import Agents

@Suite("CodexEvent Parsing")
struct CodexEventTests {

    // MARK: - Thread Events

    @Test("Parses thread/started event")
    func testThreadStarted() {
        let params: [String: Any] = ["threadId": "thr_abc123"]
        let event = CodexEvent.parse(method: "thread/started", params: params, requestId: nil)

        if case .threadStarted(let threadId) = event {
            #expect(threadId == "thr_abc123")
        } else {
            Issue.record("Expected threadStarted event")
        }
    }

    // MARK: - Turn Events

    @Test("Parses turn/started with nested turn object")
    func testTurnStartedNested() {
        let params: [String: Any] = [
            "turn": ["id": "turn_123"]
        ]
        let event = CodexEvent.parse(method: "turn/started", params: params, requestId: nil)

        if case .turnStarted(let turnId) = event {
            #expect(turnId == "turn_123")
        } else {
            Issue.record("Expected turnStarted event")
        }
    }

    @Test("Parses turn/started with flat turnId")
    func testTurnStartedFlat() {
        let params: [String: Any] = ["turnId": "turn_456"]
        let event = CodexEvent.parse(method: "turn/started", params: params, requestId: nil)

        if case .turnStarted(let turnId) = event {
            #expect(turnId == "turn_456")
        } else {
            Issue.record("Expected turnStarted event")
        }
    }

    @Test("Parses turn/completed event")
    func testTurnCompleted() {
        let params: [String: Any] = [
            "turn": ["id": "turn_789"]
        ]
        let event = CodexEvent.parse(method: "turn/completed", params: params, requestId: nil)

        if case .turnCompleted(let turnId) = event {
            #expect(turnId == "turn_789")
        } else {
            Issue.record("Expected turnCompleted event")
        }
    }

    // MARK: - Item Events

    @Test("Parses item/started event")
    func testItemStarted() {
        let params: [String: Any] = [
            "item": [
                "id": "item_001",
                "type": "commandExecution"
            ]
        ]
        let event = CodexEvent.parse(method: "item/started", params: params, requestId: nil)

        if case .itemStarted(let itemId, let type, _) = event {
            #expect(itemId == "item_001")
            #expect(type == "commandExecution")
        } else {
            Issue.record("Expected itemStarted event")
        }
    }

    @Test("Parses item/completed event")
    func testItemCompleted() {
        let params: [String: Any] = [
            "itemId": "item_001",
            "status": "completed"
        ]
        let event = CodexEvent.parse(method: "item/completed", params: params, requestId: nil)

        if case .itemCompleted(let itemId, let status, _) = event {
            #expect(itemId == "item_001")
            #expect(status == "completed")
        } else {
            Issue.record("Expected itemCompleted event")
        }
    }

    // MARK: - Agent Message Events

    @Test("Parses item/agentMessage/delta event")
    func testAgentMessageDelta() {
        let params: [String: Any] = ["delta": "Hello, I'm analyzing your code."]
        let event = CodexEvent.parse(method: "item/agentMessage/delta", params: params, requestId: nil)

        if case .agentMessageDelta(let text) = event {
            #expect(text == "Hello, I'm analyzing your code.")
        } else {
            Issue.record("Expected agentMessageDelta event")
        }
    }

    @Test("Ignores empty delta")
    func testEmptyDelta() {
        let params: [String: Any] = ["delta": ""]
        let event = CodexEvent.parse(method: "item/agentMessage/delta", params: params, requestId: nil)

        if case .unknown = event {
            // Expected
        } else {
            Issue.record("Expected unknown event for empty delta")
        }
    }

    @Test("Ignores duplicate delta events")
    func testIgnoresDuplicateDelta() {
        // These events should be ignored (they duplicate item/agentMessage/delta)
        let methods = ["codex/event/agent_message_delta", "codex/event/agent_message_content_delta"]

        for method in methods {
            let params: [String: Any] = ["delta": "Some text"]
            let event = CodexEvent.parse(method: method, params: params, requestId: nil)

            if case .unknown = event {
                // Expected - these are ignored
            } else {
                Issue.record("Expected \(method) to be ignored")
            }
        }
    }

    // MARK: - Command Output Events

    @Test("Parses command output delta")
    func testCommandOutputDelta() {
        let params: [String: Any] = [
            "itemId": "cmd_001",
            "delta": "npm install completed\n"
        ]
        let event = CodexEvent.parse(method: "item/commandExecution/outputDelta", params: params, requestId: nil)

        if case .commandOutputDelta(let itemId, let text) = event {
            #expect(itemId == "cmd_001")
            #expect(text == "npm install completed\n")
        } else {
            Issue.record("Expected commandOutputDelta event")
        }
    }

    // MARK: - Approval Events

    @Test("Parses approval request")
    func testApprovalRequest() {
        let params: [String: Any] = [
            "threadId": "thr_001",
            "turnId": "turn_001",
            "itemId": "item_001",
            "command": "npm install express"
        ]
        let event = CodexEvent.parse(method: "item/commandExecution/requestApproval", params: params, requestId: 42)

        if case .approvalRequired(let request) = event {
            #expect(request.id == 42)
            #expect(request.itemId == "item_001")
            #expect(request.command == "npm install express")
        } else {
            Issue.record("Expected approvalRequired event")
        }
    }

    @Test("Returns unknown for approval without requestId")
    func testApprovalWithoutRequestId() {
        let params: [String: Any] = ["command": "rm -rf /"]
        let event = CodexEvent.parse(method: "item/commandExecution/requestApproval", params: params, requestId: nil)

        if case .unknown = event {
            // Expected - can't respond without requestId
        } else {
            Issue.record("Expected unknown event without requestId")
        }
    }

    // MARK: - Error Events

    @Test("Parses error event")
    func testErrorEvent() {
        let params: [String: Any] = [
            "error": ["message": "Rate limit exceeded"],
            "willRetry": true
        ]
        let event = CodexEvent.parse(method: "error", params: params, requestId: nil)

        if case .turnError(let message, let willRetry) = event {
            #expect(message == "Rate limit exceeded")
            #expect(willRetry == true)
        } else {
            Issue.record("Expected turnError event")
        }
    }

    // MARK: - AgentEvent Conversion

    @Test("Converts agentMessageDelta to AgentEvent")
    func testMessageDeltaConversion() {
        let event = CodexEvent.agentMessageDelta(text: "Hello")
        let agentEvent = event.toAgentEvent()

        if case .messageDelta(let text) = agentEvent {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected AgentEvent.messageDelta")
        }
    }

    @Test("Converts turnCompleted to AgentEvent")
    func testTurnCompletedConversion() {
        let event = CodexEvent.turnCompleted(turnId: "turn_123")
        let agentEvent = event.toAgentEvent()

        if case .turnCompleted(let turnId) = agentEvent {
            #expect(turnId == "turn_123")
        } else {
            Issue.record("Expected AgentEvent.turnCompleted")
        }
    }

    @Test("Converts approvalRequired to AgentEvent")
    func testApprovalConversion() {
        let request = ApprovalRequest(
            from: [
                "itemId": "item_1",
                "command": "npm install"
            ],
            requestId: 1,
            kind: .commandExecution
        )
        let event = CodexEvent.approvalRequired(request)
        let agentEvent = event.toAgentEvent()

        if case .approvalRequired(let approval) = agentEvent {
            #expect(approval.id == "1")
            #expect(approval.command == "npm install")
            #expect(approval.source == HarnessType.codex)
        } else {
            Issue.record("Expected AgentEvent.approvalRequired")
        }
    }

    @Test("Converts commandOutputDelta to toolOutput")
    func testCommandOutputConversion() {
        let event = CodexEvent.commandOutputDelta(itemId: "cmd_1", text: "output")
        let agentEvent = event.toAgentEvent()

        if case .toolOutput(let id, let output) = agentEvent {
            #expect(id == "cmd_1")
            #expect(output == "output")
        } else {
            Issue.record("Expected AgentEvent.toolOutput")
        }
    }
}
