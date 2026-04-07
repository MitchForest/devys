// WorkspaceRunStore.swift
// Devys - Tracks active startup profile runtime per worktree.

import Foundation
import Observation
import Workspace

struct WorkspaceRunState: Equatable, Sendable {
    var profileID: StartupProfile.ID
    var terminalIDs: Set<UUID>
    var backgroundProcessIDs: Set<UUID>

    var isRunning: Bool {
        !terminalIDs.isEmpty || !backgroundProcessIDs.isEmpty
    }
}

@MainActor
@Observable
final class WorkspaceRunStore {
    private(set) var statesByWorktree: [Worktree.ID: WorkspaceRunState] = [:]

    func state(for worktreeId: Worktree.ID?) -> WorkspaceRunState? {
        guard let worktreeId else { return nil }
        return statesByWorktree[worktreeId]
    }

    func setRunning(
        worktreeId: Worktree.ID,
        profileID: StartupProfile.ID,
        terminalIDs: [UUID] = [],
        backgroundProcessIDs: [UUID] = []
    ) {
        let state = WorkspaceRunState(
            profileID: profileID,
            terminalIDs: Set(terminalIDs),
            backgroundProcessIDs: Set(backgroundProcessIDs)
        )
        guard state.isRunning else {
            statesByWorktree.removeValue(forKey: worktreeId)
            return
        }
        statesByWorktree[worktreeId] = state
    }

    func removeTerminal(_ terminalId: UUID) {
        updateStatesRemovingResource { state in
            state.terminalIDs.remove(terminalId)
        }
    }

    func removeBackgroundProcess(_ processId: UUID) {
        updateStatesRemovingResource { state in
            state.backgroundProcessIDs.remove(processId)
        }
    }

    func clearWorktree(_ worktreeId: Worktree.ID) {
        statesByWorktree.removeValue(forKey: worktreeId)
    }

    func clear() {
        statesByWorktree.removeAll()
    }

    private func updateStatesRemovingResource(_ mutation: (inout WorkspaceRunState) -> Void) {
        var updatedStates: [Worktree.ID: WorkspaceRunState] = [:]
        for (worktreeId, var state) in statesByWorktree {
            mutation(&state)
            if state.isRunning {
                updatedStates[worktreeId] = state
            }
        }
        statesByWorktree = updatedStates
    }
}
