// ContentView+StateSync.swift
// Devys - Targeted catalog/runtime synchronization helpers.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split
import SwiftUI
import Workspace

struct TabPresentationState: Equatable {
    let title: String
    let icon: String
    let activityIndicator: TabActivityIndicator?
}

@MainActor
extension ContentView {
    var uniqueEditorSessions: [EditorSession] {
        var seen: Set<ObjectIdentifier> = []
        var result: [EditorSession] = []
        for session in editorSessions.values {
            let identifier = ObjectIdentifier(session)
            if seen.insert(identifier).inserted {
                result.append(session)
            }
        }
        return result
    }

    func cleanupSession(for content: TabContent, tabId: TabID?) {
        switch content {
        case .terminal(let workspaceID, let id):
            shutdownWorkspaceTerminalSession(id: id, in: workspaceID)
        case .agentSession(let workspaceID, let sessionID):
            if let session = runtimeRegistry
                .runtimeHandle(for: workspaceID)?
                .agentRuntimeRegistry
                .session(id: sessionID) {
                Task {
                    await session.teardown()
                }
            }
            runtimeRegistry
                .runtimeHandle(for: workspaceID)?
                .agentRuntimeRegistry
                .removeSession(id: sessionID)
        case .editor:
            if let tabId {
                removeEditorSession(tabId: tabId)
            }
        default:
            break
        }
    }

    func syncTabMetadataFromSessions() {
        var nextPresentationById: [TabID: TabPresentationState] = [:]
        for (tabId, content) in tabContents {
            let presentation = currentTabPresentation(for: content, tabId: tabId)
            nextPresentationById[tabId] = presentation
            guard tabPresentationById[tabId] != presentation else { continue }
            controller.updateTab(
                tabId,
                title: presentation.title,
                icon: presentation.icon,
                activityIndicator: presentation.activityIndicator
            )
        }
        tabPresentationById = nextPresentationById
    }

    func currentTabPresentation(for content: TabContent, tabId: TabID) -> TabPresentationState {
        let (title, icon) = tabMetadata(for: content, tabId: tabId)
        return TabPresentationState(
            title: title,
            icon: icon,
            activityIndicator: tabActivityIndicator()
        )
    }

    /// Cheap structural sync: updates which repos/worktrees exist in coordinators.
    /// Does NOT trigger port scanning (lsof/ps) or git metadata refresh.
    /// Use for operations that only change structural state (terminal create/destroy,
    /// workspace selection within a loaded repo, archive/discard).
    func syncCatalogStructure() {
        runtimeRegistry.configure(container: container)
        runtimeRegistry.metadataCoordinator.syncCatalogStructure(workspaceCatalog)
        runtimeRegistry.portCoordinator.syncCatalogStructure(
            workspaceCatalog,
            managedProcessesByWorkspace: currentManagedProcessesByWorkspace()
        )
    }

    /// Port-only sync: updates port ownership data. Triggers lsof/ps but NOT
    /// git metadata refresh. Use when managed processes start/stop.
    func syncCatalogPortState() {
        runtimeRegistry.configure(container: container)
        runtimeRegistry.metadataCoordinator.syncCatalogStructure(workspaceCatalog)
        runtimeRegistry.portCoordinator.syncCatalog(
            workspaceCatalog,
            managedProcessesByWorkspace: currentManagedProcessesByWorkspace()
        )
    }

    /// Full expensive sync: triggers both port scanning AND git metadata refresh
    /// for all repositories. Only use for major structural changes (app startup,
    /// repository import, catalog refresh).
    func syncCatalogRuntimeState() {
        runtimeRegistry.configure(container: container)
        runtimeRegistry.metadataCoordinator.syncCatalog(workspaceCatalog)
        runtimeRegistry.portCoordinator.syncCatalog(
            workspaceCatalog,
            managedProcessesByWorkspace: currentManagedProcessesByWorkspace()
        )
    }

    func currentManagedProcessesByWorkspace() -> [Workspace.ID: [ManagedWorkspaceProcess]] {
        let backgroundManagedProcesses = workspaceBackgroundProcessRegistry
            .processesByWorkspace
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
            hostedSessionsByID: rehydratableHostedSessionsByID
        )
    }

    /// Metadata-only sync: updates git metadata (branch, status, diff) for
    /// worktrees but does NOT trigger port scanning. Port state will update
    /// on its periodic timer or when managed processes change.
    func syncCatalogMetadataState() {
        runtimeRegistry.configure(container: container)
        runtimeRegistry.metadataCoordinator.syncCatalog(workspaceCatalog)
        runtimeRegistry.portCoordinator.syncCatalogStructure(
            workspaceCatalog,
            managedProcessesByWorkspace: currentManagedProcessesByWorkspace()
        )
    }

    func refreshRepositoryCatalog(repositoryID: Repository.ID) async {
        await workspaceCatalog.refreshRepository(repositoryID: repositoryID)
        syncCatalogMetadataState()
    }

    func scheduleDeferredRepositoryRefresh(
        repositoryID: Repository.ID,
        workspaceID: Worktree.ID?,
        reason: String
    ) {
        Task { @MainActor in
            await Task.yield()

            guard workspaceCatalog.selectedRepositoryID == repositoryID else { return }
            if let workspaceID,
               workspaceCatalog.selectedWorkspaceID != workspaceID {
                return
            }

            var context: [String: String] = [
                "repository_id": repositoryID,
                "reason": reason
            ]
            if let workspaceID {
                context["workspace_id"] = workspaceID
            }

            let trace = WorkspacePerformanceRecorder.begin(
                "selection-refresh-deferred",
                context: context
            )
            defer {
                WorkspacePerformanceRecorder.end(trace)
            }

            await refreshRepositoryCatalog(repositoryID: repositoryID)

            guard workspaceCatalog.selectedRepositoryID == repositoryID else { return }

            if let workspaceID,
               workspaceCatalog.selectedWorkspaceID != workspaceID,
               let selectedWorktree = selectedCatalogWorktree {
                persistVisibleWorkspaceState()
                resetWorkspaceState()
                restoreWorkspaceState(for: selectedWorktree)
            }
        }
    }

    func syncTerminalNotifications() {
        workspaceTerminalRegistry.syncUnreadState()
        guard appSettings.notifications.terminalActivity else {
            workspaceAttentionStore.clearNotifications(from: .terminal)
            return
        }
        workspaceAttentionStore.syncFromTerminalRegistry(workspaceTerminalRegistry)
    }

    func markTerminalNotificationRead(_ terminalId: UUID) {
        workspaceTerminalRegistry.markRead(
            terminalId: terminalId,
            in: visibleWorkspaceID
        )
        workspaceAttentionStore.markTerminalRead(terminalId, in: visibleWorkspaceID)
    }

    func syncAttentionPreferences() {
        if appSettings.notifications.terminalActivity {
            syncTerminalNotifications()
        } else {
            workspaceAttentionStore.clearNotifications(from: .terminal)
        }

        if !appSettings.notifications.agentActivity {
            workspaceAttentionStore.clearNotifications(
                from: [.claude, .codex, .run, .build]
            )
        }
    }

    func confirmRepositorySwitchIfNeeded(to repositoryID: Repository.ID) async -> Bool {
        guard let selectedRepositoryID = workspaceCatalog.selectedRepositoryID,
              selectedRepositoryID != repositoryID else {
            return true
        }
        return await confirmCloseCurrentRepository()
    }

    func restoreSelectedWorkspaceOrReset() -> Worktree? {
        guard let selectedWorktree = selectedCatalogWorktree else {
            resetWorkspaceState()
            return nil
        }

        restoreWorkspaceState(for: selectedWorktree)
        return selectedWorktree
    }

    func selectRepository(_ repositoryID: Repository.ID) async {
        let trace = WorkspacePerformanceRecorder.begin(
            "repository-select",
            context: ["repository_id": repositoryID]
        )
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }

        if workspaceCatalog.selectedRepositoryID == repositoryID,
           let selectedWorktree = selectedCatalogWorktree,
           visibleWorkspaceID == selectedWorktree.id {
            return
        }

        guard await confirmRepositorySwitchIfNeeded(to: repositoryID) else { return }

        persistVisibleWorkspaceState()
        resetWorkspaceState()
        workspaceCatalog.selectRepository(repositoryID)
        syncCatalogStructure()

        if let selectedWorktree = restoreSelectedWorkspaceOrReset() {
            scheduleDeferredRepositoryRefresh(
                repositoryID: repositoryID,
                workspaceID: selectedWorktree.id,
                reason: "repository-select"
            )
            return
        }

        await refreshRepositoryCatalog(repositoryID: repositoryID)

        _ = restoreSelectedWorkspaceOrReset()
    }

    func moveRepository(_ repositoryID: Repository.ID, by offset: Int) {
        workspaceCatalog.moveRepository(repositoryID, by: offset)
    }

    func removeRepository(_ repositoryID: Repository.ID) async {
        guard let repository = workspaceCatalog.repository(for: repositoryID) else { return }

        let isActiveRepository = workspaceCatalog.selectedRepositoryID == repositoryID
        if isActiveRepository {
            guard await confirmCloseCurrentRepository() else { return }
            persistVisibleWorkspaceState()
            resetWorkspaceState()
        }

        recentRepositoriesService.remove(repository.rootURL)
        workspaceCatalog.removeRepository(repositoryID)
        syncCatalogRuntimeState()

        if let selectedWorktree = selectedCatalogWorktree {
            restoreWorkspaceState(for: selectedWorktree)
        }
    }

    func selectWorkspace(_ workspaceID: Worktree.ID, in repositoryID: Repository.ID) async {
        let trace = WorkspacePerformanceRecorder.begin(
            "workspace-select",
            context: [
                "workspace_id": workspaceID,
                "repository_id": repositoryID
            ]
        )
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }

        let didSwitchRepository = workspaceCatalog.selectedRepositoryID != repositoryID
        let requiresBlockingRefresh = !workspaceCatalog.canResolveWorkspaceSelection(
            workspaceID,
            in: repositoryID
        )

        if workspaceCatalog.selectedRepositoryID == repositoryID,
           visibleWorkspaceID == workspaceID {
            workspaceCatalog.selectWorkspace(workspaceID, in: repositoryID)
            syncCatalogStructure()
            return
        }

        guard await confirmRepositorySwitchIfNeeded(to: repositoryID) else { return }

        persistVisibleWorkspaceState()
        if didSwitchRepository {
            resetWorkspaceState()
        }

        if requiresBlockingRefresh {
            workspaceCatalog.selectRepository(repositoryID)
            await refreshRepositoryCatalog(repositoryID: repositoryID)
        }

        workspaceCatalog.selectWorkspace(workspaceID, in: repositoryID)
        syncCatalogStructure()

        guard let selectedWorktree = restoreSelectedWorkspaceOrReset() else { return }

        if didSwitchRepository,
           !requiresBlockingRefresh {
            scheduleDeferredRepositoryRefresh(
                repositoryID: repositoryID,
                workspaceID: selectedWorktree.id,
                reason: "workspace-select"
            )
        }
    }
}
