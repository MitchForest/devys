// WorkspaceTerminalRegistry.swift
// Devys - Workspace-owned terminal runtime registry.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import GhosttyTerminal
import Workspace

struct WorkspaceTerminalState {
    var sessionsByID: [UUID: GhosttyTerminalSession] = [:]
}

@MainActor
@Observable
final class WorkspaceTerminalRegistry {
    private(set) var statesByWorkspace: [Workspace.ID: WorkspaceTerminalState] = [:]

    func sessions(for workspaceID: Workspace.ID?) -> [UUID: GhosttyTerminalSession] {
        guard let workspaceID else { return [:] }
        return statesByWorkspace[workspaceID]?.sessionsByID ?? [:]
    }

    func session(id: UUID, in workspaceID: Workspace.ID?) -> GhosttyTerminalSession? {
        guard let workspaceID else { return nil }
        return statesByWorkspace[workspaceID]?.sessionsByID[id]
    }

    func workspaceID(for terminalId: UUID) -> Workspace.ID? {
        statesByWorkspace.first { $0.value.sessionsByID[terminalId] != nil }?.key
    }

    func createSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        attachCommand: String? = nil,
        terminateHostedSessionOnClose: Bool = true,
        id: UUID = UUID()
    ) -> GhosttyTerminalSession {
        let session = GhosttyTerminalSession(
            id: id,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            attachCommand: attachCommand,
            terminateHostedSessionOnClose: terminateHostedSessionOnClose
        )
        var state = statesByWorkspace[workspaceID] ?? WorkspaceTerminalState()
        state.sessionsByID[session.id] = session
        statesByWorkspace[workspaceID] = state
        return session
    }

    func shutdownSession(id: UUID, in workspaceID: Workspace.ID) {
        guard var state = statesByWorkspace[workspaceID] else { return }
        state.sessionsByID[id]?.shutdown()
        state.sessionsByID.removeValue(forKey: id)
        statesByWorkspace[workspaceID] = state
        cleanupWorkspaceIfEmpty(workspaceID)
    }

    func shutdownAllSessions(in workspaceID: Workspace.ID) {
        guard let state = statesByWorkspace[workspaceID] else { return }
        for session in state.sessionsByID.values {
            session.shutdown()
        }
        statesByWorkspace.removeValue(forKey: workspaceID)
    }
    private func cleanupWorkspaceIfEmpty(_ workspaceID: Workspace.ID) {
        guard let state = statesByWorkspace[workspaceID] else { return }
        guard state.sessionsByID.isEmpty else { return }
        statesByWorkspace.removeValue(forKey: workspaceID)
    }
}
