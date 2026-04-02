// RunCommandStore.swift
// Devys - Tracks per-worktree run command state.

import Foundation
import Observation
import Workspace

struct RunCommandState: Equatable, Sendable {
    var terminalId: UUID
    var isRunning: Bool
}

@MainActor
@Observable
final class RunCommandStore {
    private(set) var statesByWorktree: [Worktree.ID: RunCommandState] = [:]

    func state(for worktreeId: Worktree.ID?) -> RunCommandState? {
        guard let worktreeId else { return nil }
        return statesByWorktree[worktreeId]
    }

    func setRunning(worktreeId: Worktree.ID, terminalId: UUID) {
        statesByWorktree[worktreeId] = RunCommandState(
            terminalId: terminalId,
            isRunning: true
        )
    }

    func markStopped(worktreeId: Worktree.ID) {
        guard var state = statesByWorktree[worktreeId] else { return }
        state.isRunning = false
        statesByWorktree[worktreeId] = state
    }

    func clearTerminal(_ terminalId: UUID) {
        statesByWorktree = statesByWorktree.filter { $0.value.terminalId != terminalId }
    }

    func clear() {
        statesByWorktree.removeAll()
    }
}
