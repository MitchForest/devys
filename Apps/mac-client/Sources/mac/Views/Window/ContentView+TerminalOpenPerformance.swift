// ContentView+TerminalOpenPerformance.swift
// Devys - Terminal-open performance tracing.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import AppFeatures
import GhosttyTerminal
import Workspace

@MainActor
extension ContentView {
    func beginTerminalOpenTrace(
        sessionID: UUID,
        workspaceID: Workspace.ID?,
        source: String,
        openMode: String,
        sessionLifecycle: String,
        launchProfile: String
    ) {
        endTerminalOpenTrace(sessionID: sessionID, outcome: "replaced")

        var context: [String: String] = [
            "content_kind": "terminal",
            "source": source,
            "open_mode": openMode,
            "session_lifecycle": sessionLifecycle,
            "launch_profile": launchProfile
        ]
        if let workspaceID {
            context["workspace_id"] = workspaceID
        }

        let trace = WorkspacePerformanceRecorder.begin("terminal-open", context: context)
        var traceState = TerminalOpenTraceState(
            trace: trace,
            tracker: TerminalOpenPerformanceTracker(),
            lastCheckpoint: nil
        )
        apply(
            traceState.tracker.record(.openRequest),
            for: sessionID,
            to: &traceState
        )
    }

    func beginTerminalOpenTraceIfNeeded(
        for content: WorkspaceTabContent,
        openMode: String,
        source: String = "tab-open",
        launchProfile: String = "existing_session"
    ) {
        guard case .terminal(let workspaceID, let sessionID) = content,
              terminalOpenTraceStates[sessionID] == nil else {
            return
        }

        beginTerminalOpenTrace(
            sessionID: sessionID,
            workspaceID: workspaceID,
            source: source,
            openMode: openMode,
            sessionLifecycle: "existing",
            launchProfile: launchProfile
        )
    }

    func recordTerminalOpenCheckpoint(
        sessionID: UUID,
        _ checkpoint: TerminalOpenPerformanceTracker.Checkpoint,
        context: [String: String] = [:]
    ) {
        guard var traceState = terminalOpenTraceStates[sessionID] else { return }
        let events = traceState.tracker.record(checkpoint, context: context)
        apply(events, for: sessionID, to: &traceState)

        if checkpoint == .firstInteractiveFrame {
            endTerminalOpenTrace(sessionID: sessionID, outcome: "interactive")
        }
    }

    func endTerminalOpenTrace(
        sessionID: UUID,
        outcome: String,
        context: [String: String] = [:]
    ) {
        guard var traceState = terminalOpenTraceStates[sessionID] else { return }
        let events = traceState.tracker.finish(outcome: outcome, context: context)
        apply(events, for: sessionID, to: &traceState)
    }

    private func apply(
        _ events: [TerminalOpenPerformanceEvent],
        for sessionID: UUID,
        to traceState: inout TerminalOpenTraceState
    ) {
        guard !events.isEmpty else {
            terminalOpenTraceStates[sessionID] = traceState
            return
        }

        for event in events {
            switch event {
            case .checkpoint(let name, let context):
                traceState.lastCheckpoint = WorkspacePerformanceRecorder.checkpoint(
                    name,
                    in: traceState.trace,
                    previous: traceState.lastCheckpoint,
                    context: context
                )
            case .finish(let outcome, let context):
                WorkspacePerformanceRecorder.end(
                    traceState.trace,
                    outcome: outcome,
                    context: context
                )
                terminalOpenTraceStates.removeValue(forKey: sessionID)
                return
            }
        }

        terminalOpenTraceStates[sessionID] = traceState
    }

    func terminalPerformanceObserver(
        for sessionID: UUID
    ) -> TerminalOpenPerformanceObserver {
        { checkpoint, context in
            recordTerminalOpenCheckpoint(
                sessionID: sessionID,
                checkpoint,
                context: context
            )
        }
    }
}
