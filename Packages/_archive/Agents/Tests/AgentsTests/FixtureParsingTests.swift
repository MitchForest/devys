// FixtureParsingTests.swift
// Tests that recorded JSONL fixtures parse completely through our adapters.
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
@testable import Agents

// MARK: - Claude Code Fixture Tests

@Suite("Claude Code Fixture Parsing")
struct ClaudeCodeFixtureTests {

    @Test("All Claude Code fixtures load successfully")
    func testFixturesExist() {
        let fixtures = FixtureLoader.availableFixtures(harness: "claude-code")
        #expect(!fixtures.isEmpty, "No Claude Code fixtures found")
        #expect(fixtures.contains("simple-question"))
        #expect(fixtures.contains("read-file"))
        #expect(fixtures.contains("edit-file"))
        #expect(fixtures.contains("run-command"))
        #expect(fixtures.contains("thinking"))
    }

    @Test("Simple question fixture: all lines parse, no unknown events")
    func testSimpleQuestion() throws {
        let events = try FixtureLoader.claudeCodeAgentEvents(fixture: "simple-question")
        #expect(!events.isEmpty, "Should produce events")

        // Should have at least: sessionStarted, messageDelta(s), messageComplete, turnCompleted
        let hasSession = events.contains { if case .sessionStarted = $0 { return true }; return false }
        let hasDelta = events.contains { if case .messageDelta = $0 { return true }; return false }
        let hasTurnCompleted = events.contains { if case .turnCompleted = $0 { return true }; return false }

        #expect(hasSession, "Should have sessionStarted")
        #expect(hasDelta, "Should have messageDelta")
        #expect(hasTurnCompleted, "Should have turnCompleted")

        // No tool calls expected
        let hasToolStarted = events.contains { if case .toolStarted = $0 { return true }; return false }
        #expect(!hasToolStarted, "Simple question should not have tool calls")
    }

    @Test("Read file fixture: has tool call cycle")
    func testReadFile() throws {
        let events = try FixtureLoader.claudeCodeAgentEvents(fixture: "read-file")
        #expect(!events.isEmpty)

        let hasToolStarted = events.contains { if case .toolStarted = $0 { return true }; return false }
        let hasToolResult = events.contains { if case .toolResult = $0 { return true }; return false }
        let hasTurnCompleted = events.contains { if case .turnCompleted = $0 { return true }; return false }

        #expect(hasToolStarted, "Should have toolStarted for Read")
        #expect(hasToolResult, "Should have toolResult")
        #expect(hasTurnCompleted, "Should have turnCompleted")
    }

    @Test("Edit file fixture: has approval request")
    func testEditFile() throws {
        let events = try FixtureLoader.claudeCodeAgentEvents(fixture: "edit-file")
        #expect(!events.isEmpty)

        let hasApproval = events.contains { if case .approvalRequired = $0 { return true }; return false }
        #expect(hasApproval, "Edit should require approval")

        // Check the approval has correct tool name
        for event in events {
            if case .approvalRequired(let approval) = event {
                #expect(approval.toolName == "Edit")
                #expect(approval.source == .claudeCode)
            }
        }
    }

    @Test("Run command fixture: has approval and tool output")
    func testRunCommand() throws {
        let events = try FixtureLoader.claudeCodeAgentEvents(fixture: "run-command")
        #expect(!events.isEmpty)

        let hasApproval = events.contains { if case .approvalRequired = $0 { return true }; return false }
        let hasToolResult = events.contains { if case .toolResult = $0 { return true }; return false }

        #expect(hasApproval, "Bash should require approval")
        #expect(hasToolResult, "Should have tool result")
    }

    @Test("Thinking fixture: has reasoning deltas")
    func testThinking() throws {
        let events = try FixtureLoader.claudeCodeAgentEvents(fixture: "thinking")
        #expect(!events.isEmpty)

        let hasReasoning = events.contains { if case .reasoningDelta = $0 { return true }; return false }
        let hasDelta = events.contains { if case .messageDelta = $0 { return true }; return false }

        #expect(hasReasoning, "Should have reasoningDelta")
        #expect(hasDelta, "Should have messageDelta after thinking")
    }

    @Test("No unexpected raw/unknown events in any Claude Code fixture")
    func testNoUnknownEvents() throws {
        let fixtures = FixtureLoader.availableFixtures(harness: "claude-code")

        // These event types are legitimately mapped to .raw because they
        // carry no useful data for the UI (lifecycle markers only).
        let knownIgnorable = [
            "content_block_stop", "content_block_start",
            "message_start", "message_stop", "message_delta",
            "contentBlockStop", "contentBlockStart",
            "messageStart", "messageStop", "messageDelta",
            // control_request subtypes we handle specially
            "control_request",
        ]

        for fixture in fixtures {
            let events = try FixtureLoader.claudeCodeAgentEvents(fixture: fixture)
            let rawEvents = events.filter {
                if case .raw = $0 { return true }; return false
            }

            for raw in rawEvents {
                if case .raw(_, let type, _) = raw {
                    let isIgnorable = knownIgnorable.contains { type.lowercased().contains($0.lowercased()) }
                    if !isIgnorable {
                        Issue.record("Unexpected raw event type '\(type)' in fixture '\(fixture)'")
                    }
                }
            }
        }
    }
}

// MARK: - Codex Fixture Tests

@Suite("Codex Fixture Parsing")
struct CodexFixtureTests {

    @Test("All Codex fixtures load successfully")
    func testFixturesExist() {
        let fixtures = FixtureLoader.availableFixtures(harness: "codex")
        #expect(!fixtures.isEmpty, "No Codex fixtures found")
        #expect(fixtures.contains("simple-question"))
        #expect(fixtures.contains("run-command"))
        #expect(fixtures.contains("file-change"))
        #expect(fixtures.contains("reasoning"))
    }

    @Test("Simple question fixture: message deltas and turn completion")
    func testSimpleQuestion() throws {
        let events = try FixtureLoader.codexAgentEvents(fixture: "simple-question")
        #expect(!events.isEmpty)

        let hasDelta = events.contains { if case .messageDelta = $0 { return true }; return false }
        let hasTurnCompleted = events.contains { if case .turnCompleted = $0 { return true }; return false }

        #expect(hasDelta, "Should have messageDelta")
        #expect(hasTurnCompleted, "Should have turnCompleted")
    }

    @Test("Run command fixture: has approval and tool output")
    func testRunCommand() throws {
        let events = try FixtureLoader.codexAgentEvents(fixture: "run-command")
        #expect(!events.isEmpty)

        let hasToolStarted = events.contains { if case .toolStarted = $0 { return true }; return false }
        let hasApproval = events.contains { if case .approvalRequired = $0 { return true }; return false }
        let hasToolOutput = events.contains { if case .toolOutput = $0 { return true }; return false }
        let hasToolCompleted = events.contains { if case .toolCompleted = $0 { return true }; return false }

        #expect(hasToolStarted, "Should have toolStarted for commandExecution")
        #expect(hasApproval, "Command should require approval")
        #expect(hasToolOutput, "Should have tool output")
        #expect(hasToolCompleted, "Should have toolCompleted")
    }

    @Test("File change fixture: has patch block and approval")
    func testFileChange() throws {
        let events = try FixtureLoader.codexAgentEvents(fixture: "file-change")
        #expect(!events.isEmpty)

        let hasBlock = events.contains {
            if case .blockAdded(let block) = $0 {
                if case .patch = block { return true }
            }
            return false
        }
        let hasApproval = events.contains { if case .approvalRequired = $0 { return true }; return false }

        #expect(hasBlock, "Should have patch block for fileChange")
        #expect(hasApproval, "File change should require approval")
    }

    @Test("Reasoning fixture: has reasoning deltas")
    func testReasoning() throws {
        let events = try FixtureLoader.codexAgentEvents(fixture: "reasoning")
        #expect(!events.isEmpty)

        let hasReasoning = events.contains { if case .reasoningDelta = $0 { return true }; return false }
        #expect(hasReasoning, "Should have reasoningDelta")
    }
}
