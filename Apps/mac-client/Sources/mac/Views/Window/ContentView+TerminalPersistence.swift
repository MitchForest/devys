// ContentView+TerminalPersistence.swift
// Devys - Persistent relaunch snapshot support for repositories, layouts, and terminals.

import Foundation
import CoreGraphics
import AppFeatures
import GhosttyTerminal
import Workspace

@MainActor
extension ContentView {
    func refreshAvailableRelaunchSnapshot() {
        guard let snapshot = terminalRelaunchPersistenceStore.load(),
              snapshot.hasRepositories else {
            availableRelaunchSnapshot = nil
            return
        }

        availableRelaunchSnapshot = snapshot
    }

    func requestWindowRelaunchRestore(force: Bool) async {
        await store.send(.requestWindowRelaunchRestore(force: force)).finish()
    }

    func restorePreviousSession() async {
        await requestWindowRelaunchRestore(force: true)
    }

    func warmPersistentTerminalHostIfNeeded() async {
        guard appSettings.restore.restoreTerminalSessions else { return }
        try? await persistentTerminalHostController.ensureRunning()
    }

    func persistTerminalRelaunchSnapshotIfNeeded() {
        let hostedSessions = rehydratableHostedSessions()
        Task { @MainActor in
            await store.send(.persistWindowRelaunchSnapshot(hostedSessions)).finish()
            refreshAvailableRelaunchSnapshot()
        }
    }

    func createWorkspaceTerminalSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        tabIcon: String = "terminal",
        id: UUID = UUID()
    ) async throws -> GhosttyTerminalSession {
        if appSettings.restore.restoreTerminalSessions {
            let record = try await persistentTerminalHostController.createSession(
                id: id,
                workspaceID: workspaceID,
                workingDirectory: workingDirectory,
                launchCommand: requestedCommand
            )
            let attachCommand = await persistentTerminalHostController.attachCommand(for: record.id)
            rehydratableHostedSessionsByID[record.id] = record
            rehydratableAttachCommandsBySessionID[record.id] = attachCommand
            workspaceOperationalController.replaceHostedSessions(rehydratableHostedSessionsByID)
            return createTerminalSession(
                in: workspaceID,
                workingDirectory: workingDirectory ?? record.workingDirectory,
                stagedCommand: stagedCommand,
                attachCommand: attachCommand,
                tabIcon: tabIcon,
                id: record.id
            )
        }

        return createTerminalSession(
            in: workspaceID,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            tabIcon: tabIcon,
            id: id
        )
    }

    func shutdownWorkspaceTerminalSession(
        id: UUID,
        in workspaceID: Workspace.ID,
        terminateHostedSession: Bool = true
    ) {
        if terminateHostedSession,
           let session = workspaceTerminalRegistry.session(id: id, in: workspaceID),
           session.attachCommand != nil,
           session.terminateHostedSessionOnClose {
            Task {
                try? await persistentTerminalHostController.terminateSession(id: id)
            }
            rehydratableHostedSessionsByID.removeValue(forKey: id)
            rehydratableAttachCommandsBySessionID.removeValue(forKey: id)
            workspaceOperationalController.replaceHostedSessions(rehydratableHostedSessionsByID)
        }

        workspaceOperationalController.shutdownTerminalSession(id: id, in: workspaceID)
        store.send(.removeWorkspaceRunTerminal(id))
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    func executeWindowRelaunchRestore(
        _ request: WindowFeature.WindowRelaunchRestoreRequest
    ) async {
        let snapshot = request.snapshot
        rehydratableHostedSessionsByID = [:]
        rehydratableAttachCommandsBySessionID = [:]
        workspaceOperationalController.replaceHostedSessions([:])

        if request.settings.restoreTerminalSessions {
            await prepareRehydratableHostedSessions()
        }

        await importWindowRelaunchRepositories(
            snapshot.repositoryRootURLs.map { Repository(rootURL: $0) }
        )
        store.send(.applyWindowRelaunchRestore(request))
        rehydrateWindowRelaunchHostedContent(request)

        if let selectedWorktree = selectedCatalogWorktree {
            persistVisibleWorkspaceState()
            resetWorkspaceState()
            restoreWorkspaceState(for: selectedWorktree)
        }
    }

    private func importWindowRelaunchRepositories(_ repositories: [Repository]) async {
        var seenRepositoryIDs: Set<Repository.ID> = []
        let uniqueRepositories = repositories.filter { repository in
            seenRepositoryIDs.insert(repository.id).inserted
        }
        guard !uniqueRepositories.isEmpty else { return }
        await store.send(.openResolvedRepositories(uniqueRepositories)).finish()
        await refreshRepositoryCatalogs(uniqueRepositories.map(\.id))
    }

    private func rehydrateWindowRelaunchHostedContent(
        _ request: WindowFeature.WindowRelaunchRestoreRequest
    ) {
        guard request.settings.restoreWorkspaceLayoutAndTabs else { return }

        for workspaceState in request.snapshot.workspaceStates {
            let workspaceID = workspaceState.workspaceID
            for tabRecord in workspaceState.persistedTabs {
                switch tabRecord {
                case .terminal(let hostedSessionID):
                    guard request.settings.restoreTerminalSessions else { continue }
                    _ = rehydrateHostedSession(hostedSessionID, workspaceID: workspaceID)
                case .agent(let record):
                    guard request.settings.restoreAgentSessions else { continue }
                    restoreAgentSession(record, workspaceID: workspaceID)
                case .browser(let id, let url):
                    _ = ensureBrowserSession(id: id, in: workspaceID, initialURL: url)
                case .editor,
                     .gitDiff,
                     .workflowDefinition,
                     .workflowRun:
                    continue
                }
            }
        }
    }

    private func prepareRehydratableHostedSessions() async {
        do {
            let hostedSessions = try await persistentTerminalHostController.listSessions()
            rehydratableHostedSessionsByID = Dictionary(
                uniqueKeysWithValues: hostedSessions.map { ($0.id, $0) }
            )
            workspaceOperationalController.replaceHostedSessions(rehydratableHostedSessionsByID)

            var attachCommandsBySessionID: [UUID: String] = [:]
            for record in hostedSessions {
                attachCommandsBySessionID[record.id] = await persistentTerminalHostController.attachCommand(
                    for: record.id
                )
            }
            rehydratableAttachCommandsBySessionID = attachCommandsBySessionID
        } catch {
            rehydratableHostedSessionsByID = [:]
            rehydratableAttachCommandsBySessionID = [:]
            workspaceOperationalController.replaceHostedSessions([:])
        }
    }

    private func rehydrateHostedSession(
        _ sessionID: UUID,
        workspaceID: Workspace.ID
    ) -> Bool {
        if workspaceTerminalRegistry.session(id: sessionID, in: workspaceID) != nil {
            return true
        }

        guard let record = rehydratableHostedSessionsByID[sessionID],
              let attachCommand = rehydratableAttachCommandsBySessionID[sessionID] else {
            return false
        }

        _ = createTerminalSession(
            in: workspaceID,
            workingDirectory: record.workingDirectory,
            attachCommand: attachCommand,
            id: sessionID
        )
        return true
    }

    private func rehydratableHostedSessions() -> [HostedTerminalSessionRecord] {
        rehydratableHostedSessionsByID.values.sorted { $0.createdAt < $1.createdAt }
    }
}
