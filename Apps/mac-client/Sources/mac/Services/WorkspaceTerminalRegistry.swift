// WorkspaceTerminalRegistry.swift
// Devys - Workspace-owned terminal runtime registry.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import GhosttyTerminal
import Workspace

struct WorkspaceTerminalState {
    let workspaceID: Workspace.ID
    var sessionsByID: [UUID: GhosttyTerminalSession] = [:]
    var lastSeenBellCounts: [UUID: Int] = [:]
    var unreadTerminalIds: Set<UUID> = []
}

@MainActor
@Observable
final class WorkspaceTerminalRegistry {
    private(set) var statesByWorkspace: [Workspace.ID: WorkspaceTerminalState] = [:]

    var bellSnapshot: String {
        statesByWorkspace
            .sorted { $0.key < $1.key }
            .flatMap { workspaceID, state in
                state.sessionsByID
                    .sorted { $0.key.uuidString < $1.key.uuidString }
                    .map { terminalID, session in
                        "\(workspaceID):\(terminalID.uuidString):\(session.bellCount)"
                    }
            }
            .joined(separator: "|")
    }

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

    func unreadTerminalIds(for workspaceID: Workspace.ID?) -> Set<UUID> {
        guard let workspaceID else { return [] }
        return statesByWorkspace[workspaceID]?.unreadTerminalIds ?? []
    }

    func createSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        attachCommand: String? = nil,
        id: UUID = UUID()
    ) -> GhosttyTerminalSession {
        let session = GhosttyTerminalSession(
            id: id,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            attachCommand: attachCommand
        )
        var state = stateForWorkspace(workspaceID)
        state.sessionsByID[session.id] = session
        statesByWorkspace[workspaceID] = state
        return session
    }

    func markRead(terminalId: UUID, in workspaceID: Workspace.ID?, currentBellCount: Int? = nil) {
        guard let workspaceID,
              var state = statesByWorkspace[workspaceID]
        else { return }

        let count = currentBellCount
            ?? state.sessionsByID[terminalId]?.bellCount
            ?? state.lastSeenBellCounts[terminalId]
            ?? 0
        state.lastSeenBellCounts[terminalId] = count
        state.unreadTerminalIds.remove(terminalId)
        statesByWorkspace[workspaceID] = state
    }

    func syncUnreadState() {
        for workspaceID in Array(statesByWorkspace.keys) {
            guard var state = statesByWorkspace[workspaceID] else { continue }
            let validTerminalIds = Set(state.sessionsByID.keys)
            state.unreadTerminalIds = state.unreadTerminalIds.filter { validTerminalIds.contains($0) }
            state.lastSeenBellCounts = state.lastSeenBellCounts.filter { validTerminalIds.contains($0.key) }

            for (terminalID, session) in state.sessionsByID {
                let lastSeen = state.lastSeenBellCounts[terminalID] ?? 0
                if session.bellCount > lastSeen {
                    state.unreadTerminalIds.insert(terminalID)
                }
            }

            statesByWorkspace[workspaceID] = state
        }
    }

    func shutdownSession(id: UUID, in workspaceID: Workspace.ID) {
        guard var state = statesByWorkspace[workspaceID] else { return }
        state.sessionsByID[id]?.shutdown()
        state.sessionsByID.removeValue(forKey: id)
        state.lastSeenBellCounts.removeValue(forKey: id)
        state.unreadTerminalIds.remove(id)
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

    private func stateForWorkspace(_ workspaceID: Workspace.ID) -> WorkspaceTerminalState {
        statesByWorkspace[workspaceID] ?? WorkspaceTerminalState(workspaceID: workspaceID)
    }

    private func cleanupWorkspaceIfEmpty(_ workspaceID: Workspace.ID) {
        guard let state = statesByWorkspace[workspaceID] else { return }
        guard state.sessionsByID.isEmpty else { return }
        statesByWorkspace.removeValue(forKey: workspaceID)
    }
}
