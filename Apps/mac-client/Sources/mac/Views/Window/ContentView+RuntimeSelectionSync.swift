// ContentView+RuntimeSelectionSync.swift
// Reducer-to-runtime reconciliation for local workspace selection.
//
// Copyright © 2026 Devys. All rights reserved.

import Workspace

struct WorkspaceRuntimeSyncSnapshot: Equatable {
    let isRemoteWorkspaceSelected: Bool
    let selectedWorkspaceID: Workspace.ID?
    let selectedCatalogWorktreeID: Workspace.ID?
    let visibleWorkspaceID: Workspace.ID?
    let hasRuntimeForSelectedWorkspace: Bool
}

enum WorkspaceRuntimeSyncDecision: Equatable {
    case none
    case restoreSelectedWorkspace
    case deactivateVisibleWorkspace
}

func workspaceRuntimeSyncDecision(
    for snapshot: WorkspaceRuntimeSyncSnapshot
) -> WorkspaceRuntimeSyncDecision {
    if snapshot.isRemoteWorkspaceSelected {
        return snapshot.visibleWorkspaceID == nil ? .none : .deactivateVisibleWorkspace
    }

    guard let selectedWorkspaceID = snapshot.selectedWorkspaceID else {
        return snapshot.visibleWorkspaceID == nil ? .none : .deactivateVisibleWorkspace
    }

    guard snapshot.selectedCatalogWorktreeID == selectedWorkspaceID else {
        return .none
    }

    if snapshot.visibleWorkspaceID == selectedWorkspaceID,
       snapshot.hasRuntimeForSelectedWorkspace {
        return .none
    }

    return .restoreSelectedWorkspace
}

@MainActor
extension ContentView {
    var workspaceRuntimeSyncSnapshot: WorkspaceRuntimeSyncSnapshot {
        let selectedWorktree = selectedCatalogWorktree
        return WorkspaceRuntimeSyncSnapshot(
            isRemoteWorkspaceSelected: isRemoteWorkspaceSelected,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedCatalogWorktreeID: selectedWorktree?.id,
            visibleWorkspaceID: visibleWorkspaceID,
            hasRuntimeForSelectedWorkspace: selectedWorktree.map {
                runtimeRegistry.containsRuntime(for: $0.id)
            } ?? false
        )
    }

    func syncVisibleWorkspaceRuntimeWithReducerSelection() {
        switch workspaceRuntimeSyncDecision(for: workspaceRuntimeSyncSnapshot) {
        case .none:
            return

        case .restoreSelectedWorkspace:
            guard let selectedWorktree = selectedCatalogWorktree else { return }
            restoreWorkspaceState(for: selectedWorktree)

        case .deactivateVisibleWorkspace:
            resetVisibleWorkspaceRuntime()
        }
    }
}
