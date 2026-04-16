// ContentView+StatusBar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import SwiftUI
import UI

extension ContentView {
    /// Floating status capsule overlay positioned at the bottom center of the workspace.
    ///
    /// Shows branch name, ahead/behind counts, overall status, and agent identity dots.
    /// Auto-hides after 3 seconds, reappears on hover over the bottom edge.
    /// Expands on hover to show git action buttons and agent count.
    var statusCapsuleOverlay: some View {
        let worktree = activeWorktree
        let infoEntry = worktree.flatMap { workspaceOperationalState.metadataEntriesByWorkspaceID[$0.id] }
        let repoInfo = infoEntry?.repositoryInfo

        return StatusCapsule(
            branchName: repoInfo?.currentBranch ?? infoEntry?.branchName,
            aheadCount: repoInfo?.aheadCount ?? 0,
            behindCount: repoInfo?.behindCount ?? 0,
            agentCount: hostedAgentSessions.count,
            agentColors: hostedAgentSessions.prefix(5).indices.map { index in
                AgentColor.forIndex(index)
            },
            statusIcon: capsuleStatusIcon(infoEntry: infoEntry),
            isExpanded: $isCapsuleExpanded
        )
    }

    private func capsuleStatusIcon(infoEntry: WorktreeInfoEntry?) -> StatusIcon {
        guard let statusSummary = infoEntry?.statusSummary else { return .clean }
        if statusSummary.conflicts > 0 { return .error }
        if !statusSummary.isClean { return .warning }
        return .clean
    }
}
