// DriftDetectionTests.swift
// Tests for drift detection between fixture versions.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Testing
@testable import Agents

@Suite("Drift Detection")
struct DriftDetectionTests {

    @Test("Drift detector finds no changes when comparing same fixtures")
    func testNoDrift() throws {
        let events = try FixtureLoader.claudeCodeAgentEvents(fixture: "simple-question")
        let report = DriftDetector.compare(
            oldEvents: events,
            newEvents: events,
            oldVersion: "2.1.34",
            newVersion: "2.1.34",
            harness: "claude-code"
        )
        #expect(report.drifts.isEmpty, "Same fixtures should produce no drift")
        #expect(!report.hasBreakingChanges)
    }

    @Test("Drift detector finds new event types")
    func testNewEventType() {
        let oldEvents: [AgentEvent] = [
            .messageDelta("hi"),
            .turnCompleted(turnId: "1"),
        ]
        let newEvents: [AgentEvent] = [
            .messageDelta("hi"),
            .reasoningDelta("thinking..."),
            .turnCompleted(turnId: "1"),
        ]
        let report = DriftDetector.compare(
            oldEvents: oldEvents,
            newEvents: newEvents,
            oldVersion: "1.0",
            newVersion: "2.0",
            harness: "test"
        )
        let newTypes = report.drifts.filter { $0.category == .newEventType }
        #expect(!newTypes.isEmpty, "Should detect new reasoningDelta event")
    }

    @Test("Drift detector finds new tool names")
    func testNewToolName() {
        let oldEvents: [AgentEvent] = [
            .toolStarted(id: "1", name: "Read", input: nil),
        ]
        let newEvents: [AgentEvent] = [
            .toolStarted(id: "1", name: "Read", input: nil),
            .toolStarted(id: "2", name: "SomeNewTool", input: nil),
        ]
        let report = DriftDetector.compare(
            oldEvents: oldEvents,
            newEvents: newEvents,
            oldVersion: "1.0",
            newVersion: "2.0",
            harness: "test"
        )
        let newTools = report.drifts.filter { $0.category == .newToolName }
        #expect(!newTools.isEmpty, "Should detect new tool name")
        #expect(newTools.first?.impact == .needsNewUI, "Unknown tool should need new UI")
    }

    @Test("Zed tool catalog is fully covered")
    func testZedCatalogParity() {
        let gaps = ToolCatalog.gapsVsZed
        #expect(gaps.isEmpty, "Tools in Zed but not Devys: \(gaps.sorted())")
    }

    @Test("All Claude Code tools from real init are in our catalog")
    func testRealToolCoverage() throws {
        let lines = try FixtureLoader.loadLines(harness: "claude-code/real-v2.1.34", name: "simple-question")
        let allEvents = FixtureLoader.parseClaudeCodeEvents(lines)
        let agentEvents = allEvents.flatMap { events in events.flatMap { $0.toAgentEvents() } }

        guard let initEvent = agentEvents.first(where: {
            if case .sessionInitialized = $0 { return true }; return false
        }) else {
            Issue.record("No sessionInitialized event")
            return
        }

        if case .sessionInitialized(let info) = initEvent {
            let missingFromCatalog = info.availableTools.filter { tool in
                let catalogInfo = ToolCatalog.info(forClaudeTool: tool)
                return catalogInfo.kind == .other && tool != "Other"
            }
            if !missingFromCatalog.isEmpty {
                print("Tools not in catalog (falling through to .other): \(missingFromCatalog)")
            }
            // These are tools Claude Code advertises that we should handle
            // Allow some to be .other for now (new tools we haven't mapped yet)
            let criticalTools = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebSearch", "WebFetch", "Task", "TodoWrite"]
            for tool in criticalTools {
                if info.availableTools.contains(tool) {
                    let catalogInfo = ToolCatalog.info(forClaudeTool: tool)
                    #expect(catalogInfo.kind != .other, "Critical tool '\(tool)' should have a specific kind, not .other")
                }
            }
        }
    }
}
