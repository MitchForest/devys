// RealFixtureTests.swift
// Tests against real CLI output captured from Claude Code v2.1.34.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Testing
@testable import Agents

@Suite("Real Claude Code v2.1.34 Fixtures")
struct RealClaudeCodeFixtureTests {

    @Test("Real fixtures directory exists")
    func testRealFixturesExist() {
        let fixtures = FixtureLoader.availableFixtures(harness: "claude-code/real-v2.1.34")
        #expect(!fixtures.isEmpty, "No real fixtures found — run the recorder first")
    }

    @Test("Real simple-question: all lines parse")
    func testRealSimpleQuestion() throws {
        let lines = try FixtureLoader.loadLines(harness: "claude-code/real-v2.1.34", name: "simple-question")
        #expect(!lines.isEmpty, "Fixture is empty")

        let allEvents = FixtureLoader.parseClaudeCodeEvents(lines)
        let agentEvents = allEvents.flatMap { $0.map { $0.toAgentEvent() } }

        #expect(!agentEvents.isEmpty, "No agent events parsed")

        // Should have sessionStarted
        let hasSession = agentEvents.contains { if case .sessionStarted = $0 { return true }; return false }
        #expect(hasSession, "Should have sessionStarted")

        // Should have turnCompleted
        let hasTurnCompleted = agentEvents.contains { if case .turnCompleted = $0 { return true }; return false }
        #expect(hasTurnCompleted, "Should have turnCompleted")

        // Count raw events — these are the gaps
        let rawEvents = agentEvents.compactMap { event -> String? in
            if case .raw(let source, let type, _) = event { return "\(source):\(type)" }
            return nil
        }
        if !rawEvents.isEmpty {
            Issue.record("Raw events found (potential adapter gaps): \(Set(rawEvents).sorted())")
        }

        // Print event summary for debugging
        let summary = agentEvents.map { eventTypeName($0) }
        print("Event sequence: \(summary)")
    }

    @Test("Real read-file: tool call cycle works")
    func testRealReadFile() throws {
        let lines = try FixtureLoader.loadLines(harness: "claude-code/real-v2.1.34", name: "read-file")
        #expect(!lines.isEmpty)

        let allEvents = FixtureLoader.parseClaudeCodeEvents(lines)
        let agentEvents = allEvents.flatMap { $0.map { $0.toAgentEvent() } }

        let hasToolStarted = agentEvents.contains { if case .toolStarted = $0 { return true }; return false }
        let hasToolResult = agentEvents.contains { if case .toolResult = $0 { return true }; return false }
        let hasTurnCompleted = agentEvents.contains { if case .turnCompleted = $0 { return true }; return false }

        #expect(hasToolStarted, "Should have toolStarted for Read")
        #expect(hasToolResult, "Should have toolResult with file content")
        #expect(hasTurnCompleted, "Should have turnCompleted")

        // Verify the tool name is "Read"
        for event in agentEvents {
            if case .toolStarted(_, let name, _, _, _) = event {
                #expect(name == "Read", "Tool name should be 'Read', got '\(name)'")
            }
        }

        // Count raw events
        let rawEvents = agentEvents.compactMap { event -> String? in
            if case .raw(let source, let type, _) = event { return "\(source):\(type)" }
            return nil
        }
        if !rawEvents.isEmpty {
            Issue.record("Raw events in read-file: \(Set(rawEvents).sorted())")
        }

        let summary = agentEvents.map { eventTypeName($0) }
        print("read-file events: \(summary)")
    }

    @Test("Real run-command: bash tool call works")
    func testRealRunCommand() throws {
        let lines = try FixtureLoader.loadLines(harness: "claude-code/real-v2.1.34", name: "run-command")
        #expect(!lines.isEmpty)

        let allEvents = FixtureLoader.parseClaudeCodeEvents(lines)
        let agentEvents = allEvents.flatMap { $0.map { $0.toAgentEvent() } }

        let hasToolStarted = agentEvents.contains { if case .toolStarted = $0 { return true }; return false }
        let hasTurnCompleted = agentEvents.contains { if case .turnCompleted = $0 { return true }; return false }

        #expect(hasToolStarted, "Should have toolStarted for Bash")
        #expect(hasTurnCompleted, "Should have turnCompleted")

        // Verify bash tool name
        for event in agentEvents {
            if case .toolStarted(_, let name, _, _, _) = event {
                #expect(name == "Bash", "Tool name should be 'Bash', got '\(name)'")
            }
        }

        let rawEvents = agentEvents.compactMap { event -> String? in
            if case .raw(let source, let type, _) = event { return "\(source):\(type)" }
            return nil
        }
        if !rawEvents.isEmpty {
            Issue.record("Raw events in run-command: \(Set(rawEvents).sorted())")
        }

        let summary = agentEvents.map { eventTypeName($0) }
        print("run-command events: \(summary)")
    }

    @Test("Real system init: captures rich fields into SessionInitInfo")
    func testRealSystemInit() throws {
        let lines = try FixtureLoader.loadLines(harness: "claude-code/real-v2.1.34", name: "simple-question")
        let allEvents = FixtureLoader.parseClaudeCodeEvents(lines)
        let agentEvents = allEvents.flatMap { events in events.flatMap { $0.toAgentEvents() } }

        // Should have sessionInitialized event
        let initEvent = agentEvents.first {
            if case .sessionInitialized = $0 { return true }; return false
        }
        #expect(initEvent != nil, "Should have sessionInitialized event")

        if case .sessionInitialized(let info) = initEvent {
            #expect(info.cliVersion == "2.1.34")
            #expect(!info.availableTools.isEmpty, "Should have available tools")
            #expect(info.availableTools.contains("Read"))
            #expect(info.availableTools.contains("Edit"))
            #expect(info.availableTools.contains("Bash"))
            #expect(!info.slashCommands.isEmpty, "Should have slash commands")
            #expect(info.slashCommands.contains("compact"))
            #expect(info.slashCommands.contains("review"))
            #expect(info.permissionMode != nil)
            print("CLI version: \(info.cliVersion ?? "?")")
            print("Tools (\(info.availableTools.count)): \(info.availableTools)")
            print("Commands (\(info.slashCommands.count)): \(info.slashCommands.prefix(10))...")
        }

        // Should also have turnMetrics from the result event
        let metricsEvent = agentEvents.first {
            if case .turnMetrics = $0 { return true }; return false
        }
        #expect(metricsEvent != nil, "Should have turnMetrics event")

        if case .turnMetrics(let m) = metricsEvent {
            #expect(m.totalCostUsd != nil && m.totalCostUsd! > 0, "Should have cost")
            print("Cost: $\(m.totalCostUsd ?? 0)")
        }
    }
}

// MARK: - Real Codex v0.98.0 Fixtures

@Suite("Real Codex v0.98.0 Fixtures")
struct RealCodexFixtureTests {

    @Test("Real Codex fixtures directory exists")
    func testFixturesExist() {
        let fixtures = FixtureLoader.availableFixtures(harness: "codex/real-v0.98.0")
        #expect(!fixtures.isEmpty, "No real Codex fixtures found")
    }

    @Test("Real Codex simple-question: all lines parse")
    func testSimpleQuestion() throws {
        let lines = try FixtureLoader.loadLines(harness: "codex/real-v0.98.0", name: "simple-question")
        #expect(!lines.isEmpty)

        let events = FixtureLoader.parseCodexEvents(lines)
        let agentEvents = events.map { $0.toAgentEvent() }

        #expect(!agentEvents.isEmpty, "No events parsed")

        let hasDelta = agentEvents.contains { if case .messageDelta = $0 { return true }; return false }
        let hasTurnCompleted = agentEvents.contains { if case .turnCompleted = $0 { return true }; return false }

        #expect(hasDelta, "Should have messageDelta")
        #expect(hasTurnCompleted, "Should have turnCompleted")

        // Count raw events — adapter gaps
        let rawEvents = agentEvents.compactMap { event -> String? in
            if case .raw(let source, let type, _) = event { return "\(source):\(type)" }
            return nil
        }
        let uniqueRaw = Set(rawEvents).sorted()
        if !uniqueRaw.isEmpty {
            print("Codex simple-question raw event types: \(uniqueRaw)")
        }

        let summary = agentEvents.map { eventTypeName($0) }
        print("Codex simple-question events: \(summary)")
    }

    @Test("Real Codex read-file: has tool/command events")
    func testReadFile() throws {
        let lines = try FixtureLoader.loadLines(harness: "codex/real-v0.98.0", name: "read-file")
        #expect(!lines.isEmpty)

        let events = FixtureLoader.parseCodexEvents(lines)
        let agentEvents = events.map { $0.toAgentEvent() }

        #expect(!agentEvents.isEmpty)

        let hasTurnCompleted = agentEvents.contains { if case .turnCompleted = $0 { return true }; return false }
        #expect(hasTurnCompleted, "Should have turnCompleted")

        // Count raw events
        let rawEvents = agentEvents.compactMap { event -> String? in
            if case .raw(let source, let type, _) = event { return "\(source):\(type)" }
            return nil
        }
        let uniqueRaw = Set(rawEvents).sorted()
        if !uniqueRaw.isEmpty {
            print("Codex read-file raw event types: \(uniqueRaw)")
        }

        let summary = agentEvents.map { eventTypeName($0) }
        print("Codex read-file events: \(summary)")
    }

    @Test("Catalog new Codex event types from real output")
    func testNewCodexEventTypes() throws {
        let fixtures = FixtureLoader.availableFixtures(harness: "codex/real-v0.98.0")

        // Known intentional ignores — duplicates or low-value events
        let intentionalIgnores: Set<String> = [
            // Duplicate events we deliberately ignore (codex/event/* mirrors item/*)
            "codex/event/item_started", "codex/event/item_completed",
            "codex/event/agent_message_delta", "codex/event/agent_message_content_delta",
            "codex/event/agent_reasoning_delta", "codex/event/agent_reasoning",
            "codex/event/agent_reasoning_section_break",
            "codex/event/user_message",
            "account/rateLimits/updated",
            "item/reasoning/summaryPartAdded",
            // Intentional .raw returns for message-like items
            "tokenUsage", "mcpStartupComplete",
        ]

        var allRawTypes = Set<String>()
        for fixture in fixtures {
            if fixture.contains(".raw") { continue }
            let lines = try FixtureLoader.loadLines(harness: "codex/real-v0.98.0", name: fixture)
            let events = FixtureLoader.parseCodexEvents(lines)
            let agentEvents = events.map { $0.toAgentEvent() }

            for event in agentEvents {
                if case .raw(_, let type, _) = event {
                    allRawTypes.insert(type)
                }
            }
        }

        // Filter to only unexpected gaps
        let unexpectedGaps = allRawTypes.filter { rawType in
            // Check if this raw type matches any intentional ignore pattern
            !intentionalIgnores.contains(rawType) &&
            !rawType.hasPrefix("itemStarted:") &&    // message-like items
            !rawType.hasPrefix("itemCompleted:") &&   // message/reasoning completions
            !rawType.hasPrefix("threadStarted") &&     // thread lifecycle
            !rawType.hasPrefix("turnStarted")          // turn lifecycle
        }

        if !unexpectedGaps.isEmpty {
            print("=== REAL CODEX ADAPTER GAPS ===")
            for type in unexpectedGaps.sorted() {
                print("  - \(type)")
            }
            print("===============================")
            Issue.record("Unexpected raw event types: \(unexpectedGaps.sorted())")
        } else {
            print("=== All Codex events handled (intentional ignores: \(allRawTypes.count)) ===")
        }
    }
}

// MARK: - Helpers

private func eventTypeName(_ event: AgentEvent) -> String {
    switch event {
    case .messageDelta: return "messageDelta"
    case .messageComplete: return "messageComplete"
    case .turnCompleted: return "turnCompleted"
    case .sessionStarted: return "sessionStarted"
    case .approvalRequired: return "approvalRequired"
    case .toolStarted(_, let name, _, _, _): return "toolStarted(\(name))"
    case .toolInputDelta: return "toolInputDelta"
    case .toolOutput: return "toolOutput"
    case .toolResult: return "toolResult"
    case .toolMetadata: return "toolMetadata"
    case .toolCompleted: return "toolCompleted"
    case .error: return "error"
    case .reasoningDelta: return "reasoningDelta"
    case .sessionInitialized: return "sessionInitialized"
    case .turnMetrics: return "turnMetrics"
    case .blockAdded(let block): return "blockAdded(\(block.id.prefix(8)))"
    case .blockUpdated: return "blockUpdated"
    case .raw(_, let type, _): return "RAW(\(type))"
    }
}
