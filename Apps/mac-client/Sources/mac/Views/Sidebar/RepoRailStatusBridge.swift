// RepoRailStatusBridge.swift
// Devys - Computes StatusHint values from operational state for the repo rail.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import UI
import Workspace

/// Computes status hints per worktree from operational data.
@MainActor
func computeWorktreeStatusHints(
    worktreesByRepository: [Repository.ID: [Worktree]],
    infoEntries: [Workspace.ID: WorktreeInfoEntry],
    attentionSummaries: [Workspace.ID: WorkspaceAttentionSummary]
) -> [Worktree.ID: StatusHint] {
    var result: [Worktree.ID: StatusHint] = [:]

    for worktrees in worktreesByRepository.values {
        for worktree in worktrees {
            if let hint = computeWorktreeStatusHint(
                worktreeID: worktree.id,
                infoEntries: infoEntries,
                attentionSummaries: attentionSummaries
            ) {
                result[worktree.id] = hint
            }
        }
    }

    return result
}

private func computeWorktreeStatusHint(
    worktreeID: Worktree.ID,
    infoEntries: [Workspace.ID: WorktreeInfoEntry],
    attentionSummaries: [Workspace.ID: WorkspaceAttentionSummary]
) -> StatusHint? {
    if let attention = attentionSummaries[worktreeID], attention.hasAttention {
        return attention.waitingCount > 0 ? .attention : .attention
    }

    if let entry = infoEntries[worktreeID], let summary = entry.statusSummary {
        if summary.conflicts > 0 { return .error }
        if !summary.isClean { return .dirty }
        return .clean
    }

    return nil
}
