// ContentView+StatusBar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

extension ContentView {
    var statusBar: some View {
        let selectedWorktree = worktreeManager?.selectedWorktree
        let worktreeInfo = selectedWorktree.flatMap { worktree in
            worktreeInfoStore?.entriesById[worktree.id]
        }
        let runState = runCommandStore.state(for: selectedWorktree?.id)
        let runCommand = selectedWorktree.flatMap { worktree in
            commandSettingsStore.settings(for: worktree.repositoryRootURL).runCommand
        }
        return StatusBar(
            branchName: worktreeInfo?.branchName ?? selectedWorktree?.name,
            worktreeDetail: selectedWorktree?.detail,
            lineChanges: worktreeInfo?.lineChanges,
            pullRequest: worktreeInfo?.pullRequest,
            prAvailability: worktreeInfoStore?.isPRAvailable,
            runIsActive: runState?.isRunning == true,
            onRun: selectedWorktree == nil ? nil : { runSelectedWorktreeCommand() },
            onStop: runState?.isRunning == true ? { stopSelectedWorktreeCommand() } : nil,
            onEditRunCommand: selectedWorktree == nil ? nil : { editSelectedWorktreeRunCommand() },
            onClearRunCommand: (runCommand?.isEmpty == false)
                ? { clearSelectedWorktreeRunCommand() }
                : nil
        )
    }
}
