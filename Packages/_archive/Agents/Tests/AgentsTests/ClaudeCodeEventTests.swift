// ClaudeCodeEventTests.swift
// Tests for Claude Code NDJSON event parsing.
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
@testable import Agents

@Suite("ClaudeCodeEvent Parsing")
struct ClaudeCodeEventTests {

    // MARK: - Session Events

    @Test("Parses system init event")
    func testSystemInit() {
        let json: [String: Any] = [
            "type": "system",
            "subtype": "init",
            "session_id": "abc123",
            "model": "claude-opus-4-5-20251101"
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .sessionStarted(let sessionId, let model, _) = events[0] {
            #expect(sessionId == "abc123")
            #expect(model == "claude-opus-4-5-20251101")
        } else {
            Issue.record("Expected sessionStarted event")
        }
    }

    // MARK: - Streaming Events

    @Test("Parses content_block_delta text event")
    func testStreamDelta() {
        let json: [String: Any] = [
            "type": "stream_event",
            "event": [
                "type": "content_block_delta",
                "delta": [
                    "type": "text_delta",
                    "text": "Hello, world!"
                ]
            ]
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .messageDelta(let text) = events[0] {
            #expect(text == "Hello, world!")
        } else {
            Issue.record("Expected messageDelta event")
        }
    }

    @Test("Ignores empty delta text")
    func testEmptyDelta() {
        let json: [String: Any] = [
            "type": "stream_event",
            "event": [
                "type": "content_block_delta",
                "delta": [
                    "type": "text_delta",
                    "text": ""
                ]
            ]
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.isEmpty)
    }

    // MARK: - Assistant Message Events

    @Test("Parses assistant text content")
    func testAssistantTextContent() {
        let json: [String: Any] = [
            "type": "assistant",
            "message": [
                "content": [
                    ["type": "text", "text": "Here is the answer."]
                ]
            ]
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .messageComplete(let text) = events[0] {
            #expect(text == "Here is the answer.")
        } else {
            Issue.record("Expected messageComplete event")
        }
    }

    @Test("Parses tool_use in assistant message")
    func testToolUse() {
        let json: [String: Any] = [
            "type": "assistant",
            "message": [
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool_123",
                        "name": "bash",
                        "input": ["command": "ls -la"]
                    ]
                ]
            ]
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .toolUse(let id, let name, let input) = events[0] {
            #expect(id == "tool_123")
            #expect(name == "bash")
            #expect(input != nil)
        } else {
            Issue.record("Expected toolUse event")
        }
    }

    // MARK: - Permission Events

    @Test("Parses permission_request event")
    func testPermissionRequest() {
        let json: [String: Any] = [
            "type": "permission_request",
            "request_id": "req_456",
            "command": "rm -rf /tmp/test"
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .permissionRequest(let request) = events[0] {
            #expect(request.id == "req_456")
            #expect(request.command == "rm -rf /tmp/test")
        } else {
            Issue.record("Expected permissionRequest event")
        }
    }

    // MARK: - Result Events

    @Test("Parses success result")
    func testSuccessResult() {
        let json: [String: Any] = [
            "type": "result",
            "subtype": "success"
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .result(let subtype, _) = events[0] {
            #expect(subtype == "success")
        } else {
            Issue.record("Expected result event")
        }
    }

    // MARK: - Error Events

    @Test("Parses error event")
    func testErrorEvent() {
        let json: [String: Any] = [
            "type": "error",
            "message": "API rate limit exceeded"
        ]

        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .error(let message) = events[0] {
            #expect(message == "API rate limit exceeded")
        } else {
            Issue.record("Expected error event")
        }
    }

    // MARK: - AgentEvent Conversion

    @Test("Parses system init with rich fields")
    func testSystemInitRichFields() {
        let json: [String: Any] = [
            "type": "system",
            "subtype": "init",
            "session_id": "abc123",
            "model": "claude-sonnet-4-20250514",
            "claude_code_version": "2.1.34",
            "tools": ["Read", "Write", "Edit", "Bash"],
            "slash_commands": ["compact", "review", "init"],
            "skills": ["debug", "deploy"],
            "agents": ["Bash", "Explore"],
            "permissionMode": "default",
            "cwd": "/tmp/test",
            "apiKeySource": "/login managed key"
        ]
        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .sessionStarted(_, _, let initInfo) = events[0] {
            #expect(initInfo?.cliVersion == "2.1.34")
            #expect(initInfo?.availableTools == ["Read", "Write", "Edit", "Bash"])
            #expect(initInfo?.slashCommands == ["compact", "review", "init"])
            #expect(initInfo?.permissionMode == "default")
        } else {
            Issue.record("Expected sessionStarted with initInfo")
        }
    }

    @Test("Parses result event with metrics")
    func testResultWithMetrics() {
        let json: [String: Any] = [
            "type": "result",
            "subtype": "success",
            "is_error": false,
            "duration_ms": 3623,
            "duration_api_ms": 3516,
            "total_cost_usd": 0.0208,
            "num_turns": 2,
            "permission_denials": [] as [String]
        ]
        let events = ClaudeCodeEvent.parseEvents(from: json)
        #expect(events.count == 1)

        if case .result(let subtype, let metrics) = events[0] {
            #expect(subtype == "success")
            #expect(metrics?.durationMs == 3623)
            #expect(metrics?.totalCostUsd == 0.0208)
        } else {
            Issue.record("Expected result with metrics")
        }
    }

    // MARK: - AgentEvent Conversion

    @Test("Converts messageDelta to AgentEvent")
    func testMessageDeltaConversion() {
        let event = ClaudeCodeEvent.messageDelta(text: "Hello")
        let agentEvent = event.toAgentEvent()

        if case .messageDelta(let text) = agentEvent {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected AgentEvent.messageDelta")
        }
    }

    @Test("Converts permissionRequest to approvalRequired")
    func testPermissionConversion() {
        let event = ClaudeCodeEvent.permissionRequest(
            ClaudePermissionRequest(
                id: "req_1",
                toolName: nil,
                command: "npm install",
                input: nil,
                suggestions: [],
                blockedPath: nil,
                decisionReason: nil,
                toolUseId: nil
            )
        )
        let agentEvent = event.toAgentEvent()

        if case .approvalRequired(let approval) = agentEvent {
            #expect(approval.id == "req_1")
            #expect(approval.command == "npm install")
            #expect(approval.source == .claudeCode)
        } else {
            Issue.record("Expected AgentEvent.approvalRequired")
        }
    }

    @Test("Converts success result to turnCompleted")
    func testSuccessResultConversion() {
        let event = ClaudeCodeEvent.result(subtype: "success", metrics: nil)
        let agentEvent = event.toAgentEvent()

        if case .turnCompleted = agentEvent {
            // Success
        } else {
            Issue.record("Expected AgentEvent.turnCompleted")
        }
    }
}
