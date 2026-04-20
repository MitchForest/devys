// TerminalOpenPerformanceTracker.swift
// Devys - Terminal-open performance milestones and outcome classification.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

enum TerminalOpenPerformanceEvent: Equatable {
    case checkpoint(name: String, context: [String: String])
    case finish(outcome: String, context: [String: String])
}

typealias TerminalOpenPerformanceObserver = @MainActor @Sendable (
    TerminalOpenPerformanceTracker.Checkpoint,
    [String: String]
) -> Void

struct TerminalOpenPerformanceTracker {
    enum Checkpoint: String, CaseIterable {
        case openRequest = "open_request"
        case tabVisible = "tab_visible"
        case controllerCreated = "controller_created"
        case hostEnsureStart = "host_ensure_start"
        case hostReady = "host_ready"
        case sessionCreateStart = "session_create_start"
        case sessionCreated = "session_created"
        case viewportMeasured = "viewport_measured"
        case viewportApplied = "viewport_applied"
        case attachStart = "attach_start"
        case attachAck = "attach_ack"
        case firstOutputChunk = "first_output_chunk"
        case firstSurfaceUpdate = "first_surface_update"
        case firstAtlasMutation = "first_atlas_mutation"
        case firstFrameCommit = "first_frame_commit"
        case firstInteractiveFrame = "first_interactive_frame"
    }

    private var markedCheckpoints = Set<Checkpoint>()
    private var hasFinished = false

    mutating func record(
        _ checkpoint: Checkpoint,
        context: [String: String] = [:]
    ) -> [TerminalOpenPerformanceEvent] {
        guard !hasFinished else { return [] }
        guard markedCheckpoints.insert(checkpoint).inserted else { return [] }
        return [
            .checkpoint(
                name: checkpoint.rawValue,
                context: context
            )
        ]
    }

    mutating func finish(
        outcome: String,
        context: [String: String] = [:]
    ) -> [TerminalOpenPerformanceEvent] {
        guard !hasFinished else { return [] }
        hasFinished = true
        return [
            .finish(
                outcome: outcome,
                context: context
            )
        ]
    }
}
