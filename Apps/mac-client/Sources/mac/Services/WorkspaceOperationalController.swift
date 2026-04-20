// WorkspaceOperationalController.swift
// Devys - Live operational boundary for reducer-owned workspace state.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import GhosttyTerminal
import Observation
import Workspace

@MainActor
final class WorkspaceOperationalController {
    let metadataCoordinator: WorktreeMetadataCoordinator
    let portCoordinator: WorkspacePortOwnershipCoordinator
    let terminalRegistry: WorkspaceTerminalRegistry
    let backgroundProcessRegistry: WorkspaceBackgroundProcessRegistry

    private var catalogContext = WorkspaceOperationalCatalogContext()
    private var hostedSessionsByID: [UUID: HostedTerminalSessionRecord] = [:]
    private var lastSeenBellCountsByWorkspaceID: [Workspace.ID: [UUID: Int]] = [:]
    private var snapshotContinuations: [UUID: AsyncStream<WorkspaceOperationalSnapshot>.Continuation] = [:]
    private var isObservingOperationalState = false
    private var isObservingPortOwnershipInputs = false

    init(
        metadataCoordinator: WorktreeMetadataCoordinator = WorktreeMetadataCoordinator(),
        portCoordinator: WorkspacePortOwnershipCoordinator = WorkspacePortOwnershipCoordinator(),
        terminalRegistry: WorkspaceTerminalRegistry = WorkspaceTerminalRegistry(),
        backgroundProcessRegistry: WorkspaceBackgroundProcessRegistry = WorkspaceBackgroundProcessRegistry()
    ) {
        self.metadataCoordinator = metadataCoordinator
        self.portCoordinator = portCoordinator
        self.terminalRegistry = terminalRegistry
        self.backgroundProcessRegistry = backgroundProcessRegistry
    }

    func updates() -> AsyncStream<WorkspaceOperationalSnapshot> {
        ensureObservationStarted()

        let streamID = UUID()
        return AsyncStream { continuation in
            snapshotContinuations[streamID] = continuation
            continuation.yield(makeSnapshot())
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.snapshotContinuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    func sync(
        _ context: WorkspaceOperationalCatalogContext,
        mode: WorkspaceOperationalSyncMode
    ) {
        catalogContext = context
        let snapshot = WindowCatalogRuntimeSnapshot(
            repositories: context.repositories,
            worktreesByRepository: context.worktreesByRepository,
            selectedRepositoryID: context.selectedRepositoryID,
            selectedWorkspaceID: context.selectedWorkspaceID
        )

        switch mode {
        case .structure:
            metadataCoordinator.syncCatalogStructure(snapshot)
            portCoordinator.syncCatalogStructure(
                snapshot,
                managedProcessesByWorkspace: managedProcessesByWorkspace()
            )
        case .metadata:
            metadataCoordinator.syncCatalog(snapshot)
            portCoordinator.syncCatalogStructure(
                snapshot,
                managedProcessesByWorkspace: managedProcessesByWorkspace()
            )
        case .ports:
            metadataCoordinator.syncCatalogStructure(snapshot)
            portCoordinator.syncCatalog(
                snapshot,
                managedProcessesByWorkspace: managedProcessesByWorkspace()
            )
        case .all:
            metadataCoordinator.syncCatalog(snapshot)
            portCoordinator.syncCatalog(
                snapshot,
                managedProcessesByWorkspace: managedProcessesByWorkspace()
            )
        }

        broadcastSnapshot()
    }

    func markTerminalRead(
        _ terminalID: UUID,
        in workspaceID: Workspace.ID?
    ) {
        guard let workspaceID,
              let session = terminalRegistry.session(id: terminalID, in: workspaceID)
        else { return }

        var workspaceCounts = lastSeenBellCountsByWorkspaceID[workspaceID] ?? [:]
        workspaceCounts[terminalID] = session.bellCount
        lastSeenBellCountsByWorkspaceID[workspaceID] = workspaceCounts
        broadcastSnapshot()
    }

    func requestMetadataRefresh(
        worktreeIDs: [Workspace.ID],
        repositoryID: Repository.ID?
    ) {
        metadataCoordinator.refresh(worktreeIds: worktreeIDs, in: repositoryID)
        broadcastSnapshot()
    }

    func clearWorkspace(_ workspaceID: Workspace.ID) {
        portCoordinator.clearWorkspace(workspaceID)
        hostedSessionsByID = hostedSessionsByID.filter { $0.value.workspaceID != workspaceID }
        lastSeenBellCountsByWorkspaceID.removeValue(forKey: workspaceID)
        broadcastSnapshot()
    }

    func createTerminalSession(
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
        let session = terminalRegistry.createSession(
            in: workspaceID,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            tabIcon: tabIcon,
            terminateHostedSessionOnClose: terminateHostedSessionOnClose,
            startupPhase: startupPhase,
            preferredViewportSize: preferredViewportSize,
            id: id
        )
        broadcastSnapshot()
        return session
    }

    func shutdownTerminalSession(
        id: UUID,
        in workspaceID: Workspace.ID
    ) {
        terminalRegistry.shutdownSession(id: id, in: workspaceID)
        lastSeenBellCountsByWorkspaceID[workspaceID]?.removeValue(forKey: id)
        if lastSeenBellCountsByWorkspaceID[workspaceID]?.isEmpty == true {
            lastSeenBellCountsByWorkspaceID.removeValue(forKey: workspaceID)
        }
        broadcastSnapshot()
    }

    func replaceHostedSessions(_ sessionsByID: [UUID: HostedTerminalSessionRecord]) {
        hostedSessionsByID = sessionsByID
        syncCurrentPortOwnership()
        broadcastSnapshot()
    }

    func upsertHostedSession(_ session: HostedTerminalSessionRecord) {
        hostedSessionsByID[session.id] = session
        syncCurrentPortOwnership()
        broadcastSnapshot()
    }

    func removeHostedSession(_ sessionID: UUID) {
        hostedSessionsByID.removeValue(forKey: sessionID)
        syncCurrentPortOwnership()
        broadcastSnapshot()
    }
}

@MainActor
private extension WorkspaceOperationalController {
    func ensureObservationStarted() {
        guard !isObservingOperationalState else { return }
        isObservingOperationalState = true
        observeOperationalState()
        observePortOwnershipInputs()
    }

    func observeOperationalState() {
        withObservationTracking {
            _ = metadataCoordinator.entriesByWorkspaceID
            _ = portCoordinator.portsByWorkspaceID
            _ = portCoordinator.summariesByWorkspaceID
            _ = terminalUnreadSnapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.broadcastSnapshot()
                self?.observeOperationalState()
            }
        }
    }

    func broadcastSnapshot() {
        let snapshot = makeSnapshot()
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    func observePortOwnershipInputs() {
        guard !isObservingPortOwnershipInputs else { return }
        isObservingPortOwnershipInputs = true
        trackPortOwnershipInputs()
    }

    func trackPortOwnershipInputs() {
        withObservationTracking {
            _ = backgroundProcessRegistry.processesByWorkspace
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncCurrentPortOwnership()
                self?.broadcastSnapshot()
                self?.trackPortOwnershipInputs()
            }
        }
    }

    func makeSnapshot() -> WorkspaceOperationalSnapshot {
        WorkspaceOperationalSnapshot(
            metadataEntriesByWorkspaceID: metadataCoordinator.entriesByWorkspaceID,
            portsByWorkspaceID: portCoordinator.portsByWorkspaceID,
            portSummariesByWorkspaceID: portCoordinator.summariesByWorkspaceID,
            unreadTerminalIDsByWorkspaceID: terminalUnreadSnapshot()
        )
    }

    func terminalUnreadSnapshot() -> [Workspace.ID: Set<UUID>] {
        var unreadByWorkspace: [Workspace.ID: Set<UUID>] = [:]

        for (workspaceID, state) in terminalRegistry.statesByWorkspace {
            let validTerminalIDs = Set(state.sessionsByID.keys)
            var workspaceCounts = lastSeenBellCountsByWorkspaceID[workspaceID] ?? [:]
            workspaceCounts = workspaceCounts.filter { validTerminalIDs.contains($0.key) }

            var unread: Set<UUID> = []
            for (terminalID, session) in state.sessionsByID {
                let lastSeen = workspaceCounts[terminalID] ?? 0
                if session.bellCount > lastSeen {
                    unread.insert(terminalID)
                }
            }

            lastSeenBellCountsByWorkspaceID[workspaceID] = workspaceCounts
            if !unread.isEmpty {
                unreadByWorkspace[workspaceID] = unread
            }
        }

        let activeWorkspaceIDs = Set(terminalRegistry.statesByWorkspace.keys)
        for workspaceID in lastSeenBellCountsByWorkspaceID.keys where !activeWorkspaceIDs.contains(workspaceID) {
            lastSeenBellCountsByWorkspaceID.removeValue(forKey: workspaceID)
        }

        return unreadByWorkspace
    }

    func managedProcessesByWorkspace() -> [Workspace.ID: [ManagedWorkspaceProcess]] {
        let backgroundManagedProcesses = backgroundProcessRegistry.processesByWorkspace
            .mapValues { processes in
                processes.values.map { process in
                    ManagedWorkspaceProcess(
                        processID: process.process.processIdentifier,
                        displayName: process.displayName
                    )
                }
            }

        return WorkspacePortManagedProcessCatalog.makeManagedProcesses(
            backgroundProcessesByWorkspace: backgroundManagedProcesses,
            hostedSessionsByID: hostedSessionsByID
        )
    }

    func syncCurrentPortOwnership() {
        let snapshot = WindowCatalogRuntimeSnapshot(
            repositories: catalogContext.repositories,
            worktreesByRepository: catalogContext.worktreesByRepository,
            selectedRepositoryID: catalogContext.selectedRepositoryID,
            selectedWorkspaceID: catalogContext.selectedWorkspaceID
        )
        portCoordinator.syncCatalog(
            snapshot,
            managedProcessesByWorkspace: managedProcessesByWorkspace()
        )
    }
}
