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
    var controllersByID: [UUID: HostedLocalTerminalController] = [:]
    var preferredViewportSizesByID: [UUID: HostedTerminalViewportSize] = [:]
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

    func controller(id: UUID, in workspaceID: Workspace.ID?) -> HostedLocalTerminalController? {
        guard let workspaceID else { return nil }
        return statesByWorkspace[workspaceID]?.controllersByID[id]
    }

    func workspaceID(for terminalId: UUID) -> Workspace.ID? {
        statesByWorkspace.first { $0.value.sessionsByID[terminalId] != nil }?.key
    }

    func createSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        tabIcon: String = "terminal",
        terminateHostedSessionOnClose: Bool = true,
        startupPhase: GhosttyTerminalStartupPhase = .startingShell,
        preferredViewportSize: HostedTerminalViewportSize? = nil,
        id: UUID = UUID()
    ) -> GhosttyTerminalSession {
        let session = GhosttyTerminalSession(
            id: id,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            tabIcon: tabIcon,
            terminateHostedSessionOnClose: terminateHostedSessionOnClose,
            startupPhase: startupPhase
        )
        var state = statesByWorkspace[workspaceID] ?? WorkspaceTerminalState()
        state.sessionsByID[session.id] = session
        if let preferredViewportSize {
            state.preferredViewportSizesByID[session.id] = preferredViewportSize
        }
        statesByWorkspace[workspaceID] = state
        return session
    }

    func ensureController(
        for sessionID: UUID,
        in workspaceID: Workspace.ID,
        socketPath: String,
        appearance: GhosttyTerminalAppearance,
        performanceObserver: TerminalOpenPerformanceObserver? = nil
    ) -> HostedLocalTerminalController? {
        guard var state = statesByWorkspace[workspaceID],
              let session = state.sessionsByID[sessionID]
        else {
            return nil
        }

        if let existing = state.controllersByID[sessionID] {
            existing.updateAppearance(appearance)
            existing.updatePerformanceObserver(performanceObserver)
            return existing
        }

        let controller = HostedLocalTerminalController(
            session: session,
            socketPath: socketPath,
            appearance: appearance,
            performanceObserver: performanceObserver,
            preferredViewportSize: state.preferredViewportSizesByID[sessionID]
        )
        state.controllersByID[sessionID] = controller
        statesByWorkspace[workspaceID] = state
        return controller
    }

    func updateAppearance(_ appearance: GhosttyTerminalAppearance) {
        for state in statesByWorkspace.values {
            for controller in state.controllersByID.values {
                controller.updateAppearance(appearance)
            }
        }
    }

    func shutdownSession(id: UUID, in workspaceID: Workspace.ID) {
        guard var state = statesByWorkspace[workspaceID] else { return }
        state.controllersByID[id]?.detach()
        state.controllersByID.removeValue(forKey: id)
        state.preferredViewportSizesByID.removeValue(forKey: id)
        state.sessionsByID[id]?.shutdown()
        state.sessionsByID.removeValue(forKey: id)
        statesByWorkspace[workspaceID] = state
        cleanupWorkspaceIfEmpty(workspaceID)
    }

    func shutdownAllSessions(in workspaceID: Workspace.ID) {
        guard let state = statesByWorkspace[workspaceID] else { return }
        for controller in state.controllersByID.values {
            controller.detach()
        }
        for session in state.sessionsByID.values {
            session.shutdown()
        }
        statesByWorkspace.removeValue(forKey: workspaceID)
    }
    private func cleanupWorkspaceIfEmpty(_ workspaceID: Workspace.ID) {
        guard let state = statesByWorkspace[workspaceID] else { return }
        guard state.sessionsByID.isEmpty, state.controllersByID.isEmpty else { return }
        statesByWorkspace.removeValue(forKey: workspaceID)
    }
}
