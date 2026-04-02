// DriftDetector.swift
// Compares two fixture sets and produces a drift report.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
@testable import Agents

/// Compares two sets of recorded fixtures to detect protocol drift.
///
/// Run after updating CLI versions to identify:
/// - New event types that need adapter support
/// - Removed event types (dead code)
/// - New tool names that need ToolCatalog entries
/// - Schema changes in known events
struct DriftDetector {

    struct DriftReport: Codable {
        let oldVersion: String
        let newVersion: String
        let harness: String
        let drifts: [Drift]
        let timestamp: Date

        var hasBreakingChanges: Bool {
            drifts.contains { $0.impact == .needsAdapter || $0.impact == .needsNewUI }
        }
    }

    struct Drift: Codable {
        let category: Category
        let detail: String
        let impact: Impact
    }

    enum Category: String, Codable {
        case newEventType
        case removedEventType
        case newToolName
        case removedToolName
        case newJsonField
        case eventCountChange
    }

    enum Impact: String, Codable {
        case needsNewUI
        case needsAdapter
        case cosmetic
        case info
    }

    /// Compares agent events from two fixture sets.
    static func compare(
        oldEvents: [AgentEvent],
        newEvents: [AgentEvent],
        oldVersion: String,
        newVersion: String,
        harness: String
    ) -> DriftReport {
        var drifts: [Drift] = []

        // 1. Compare event type distribution
        let oldTypes = eventTypeDistribution(oldEvents)
        let newTypes = eventTypeDistribution(newEvents)

        let oldTypeNames = Set(oldTypes.keys)
        let newTypeNames = Set(newTypes.keys)

        for newType in newTypeNames.subtracting(oldTypeNames) {
            drifts.append(Drift(
                category: .newEventType,
                detail: "New event type: \(newType) (count: \(newTypes[newType] ?? 0))",
                impact: newType.hasPrefix("RAW") ? .needsAdapter : .info
            ))
        }

        for removedType in oldTypeNames.subtracting(newTypeNames) {
            drifts.append(Drift(
                category: .removedEventType,
                detail: "Removed event type: \(removedType)",
                impact: .info
            ))
        }

        // 2. Compare tool names seen
        let oldTools = toolNames(oldEvents)
        let newTools = toolNames(newEvents)

        for newTool in newTools.subtracting(oldTools) {
            let inCatalog = ToolCatalog.handledToolNames.contains(newTool)
            drifts.append(Drift(
                category: .newToolName,
                detail: "New tool: \(newTool) (in catalog: \(inCatalog))",
                impact: inCatalog ? .info : .needsNewUI
            ))
        }

        for removedTool in oldTools.subtracting(newTools) {
            drifts.append(Drift(
                category: .removedToolName,
                detail: "Removed tool: \(removedTool)",
                impact: .cosmetic
            ))
        }

        return DriftReport(
            oldVersion: oldVersion,
            newVersion: newVersion,
            harness: harness,
            drifts: drifts,
            timestamp: Date()
        )
    }

    // MARK: - Helpers

    private static func eventTypeDistribution(_ events: [AgentEvent]) -> [String: Int] {
        var dist: [String: Int] = [:]
        for event in events {
            let name = eventTypeName(event)
            dist[name, default: 0] += 1
        }
        return dist
    }

    private static func toolNames(_ events: [AgentEvent]) -> Set<String> {
        var tools = Set<String>()
        for event in events {
            if case .toolStarted(_, let name, _, _, _) = event {
                tools.insert(name)
            }
        }
        return tools
    }

    private static func eventTypeName(_ event: AgentEvent) -> String {
        switch event {
        case .messageDelta: return "messageDelta"
        case .messageComplete: return "messageComplete"
        case .turnCompleted: return "turnCompleted"
        case .sessionStarted: return "sessionStarted"
        case .sessionInitialized: return "sessionInitialized"
        case .turnMetrics: return "turnMetrics"
        case .approvalRequired: return "approvalRequired"
        case .toolStarted: return "toolStarted"
        case .toolInputDelta: return "toolInputDelta"
        case .toolOutput: return "toolOutput"
        case .toolResult: return "toolResult"
        case .toolMetadata: return "toolMetadata"
        case .toolCompleted: return "toolCompleted"
        case .error: return "error"
        case .reasoningDelta: return "reasoningDelta"
        case .blockAdded: return "blockAdded"
        case .blockUpdated: return "blockUpdated"
        case .raw(_, let type, _): return "RAW(\(type))"
        }
    }
}
