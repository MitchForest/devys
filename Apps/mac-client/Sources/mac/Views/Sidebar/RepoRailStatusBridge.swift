// RepoRailStatusBridge.swift
// Devys - Computes StatusHint values from operational state for the repo rail.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import UI
import Workspace

/// Computes aggregate status hints per repository from worktree operational data.
@MainActor
func computeRepoStatusHints(
    repositories: [Repository],
    worktreesByRepository: [Repository.ID: [Worktree]],
    infoEntries: [Workspace.ID: WorktreeInfoEntry],
    attentionSummaries: [Workspace.ID: WorkspaceAttentionSummary]
) -> [Repository.ID: StatusHint] {
    var result: [Repository.ID: StatusHint] = [:]

    for repo in repositories {
        let worktrees = worktreesByRepository[repo.id] ?? []
        var worst: StatusHint = .clean

        for worktree in worktrees {
            let hint = computeWorktreeStatusHint(
                worktreeID: worktree.id,
                infoEntries: infoEntries,
                attentionSummaries: attentionSummaries
            )
            if let hint {
                worst = worseHint(worst, hint)
            }
        }

        result[repo.id] = worst
    }

    return result
}

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

private func worseHint(_ a: StatusHint, _ b: StatusHint) -> StatusHint {
    let priority: [StatusHint: Int] = [.clean: 0, .dirty: 1, .attention: 2, .error: 3]
    return (priority[b] ?? 0) > (priority[a] ?? 0) ? b : a
}
