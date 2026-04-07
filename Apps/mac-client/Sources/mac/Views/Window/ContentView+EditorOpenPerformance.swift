// ContentView+EditorOpenPerformance.swift
// Devys - Editor-open performance tracing.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split
import Workspace

@MainActor
extension ContentView {
    func beginEditorOpenTrace(
        tabId: TabID,
        url: URL,
        workspaceID: Workspace.ID?,
        openMode: String
    ) {
        endEditorOpenTrace(tabId: tabId, outcome: "replaced")

        var context: [String: String] = [
            "content_kind": "editor",
            "file_extension": url.pathExtension.isEmpty ? "none" : url.pathExtension,
            "open_mode": openMode
        ]
        if let workspaceID {
            context["workspace_id"] = workspaceID
        }

        let trace = WorkspacePerformanceRecorder.begin("editor-open", context: context)
        editorOpenTraceStates[tabId] = EditorOpenTraceState(
            trace: trace,
            tracker: EditorOpenPerformanceTracker(),
            lastCheckpoint: nil
        )
    }

    func recordEditorOpenPresentation(
        tabId: TabID,
        snapshot: EditorOpenPerformanceSnapshot?
    ) {
        guard let snapshot,
              var traceState = editorOpenTraceStates[tabId] else {
            return
        }

        let events = traceState.tracker.recordPresentation(snapshot)
        apply(events, for: tabId, to: &traceState)
    }

    func endEditorOpenTrace(tabId: TabID, outcome: String) {
        guard var traceState = editorOpenTraceStates[tabId] else { return }
        let events = traceState.tracker.finish(outcome: outcome)
        apply(events, for: tabId, to: &traceState)
    }

    private func apply(
        _ events: [EditorOpenPerformanceEvent],
        for tabId: TabID,
        to traceState: inout EditorOpenTraceState
    ) {
        guard !events.isEmpty else { return }

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
                editorOpenTraceStates.removeValue(forKey: tabId)
                return
            }
        }

        editorOpenTraceStates[tabId] = traceState
    }
}
