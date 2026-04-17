// ContentView+StateSync.swift
// Devys - Reducer-first catalog/runtime bridge helpers.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import Split
import SwiftUI
import Workspace

struct TabPresentationState: Equatable {
    let title: String
    let icon: String
    let isPreview: Bool
    let isDirty: Bool
    let activityIndicator: TabActivityIndicator?
}

@MainActor
extension ContentView {
    func windowWorkspaceContext(
        for workspaceID: Workspace.ID
    ) -> (repository: Repository, worktree: Worktree)? {
        guard let repository = store.repositories.first(where: { repository in
            store.worktreesByRepository[repository.id]?.contains { $0.id == workspaceID } == true
        }),
        let worktree = store.worktreesByRepository[repository.id]?.first(where: { $0.id == workspaceID }) else {
            return nil
        }

        return (repository, worktree)
    }

    func syncFilesSidebarVisibilityFromReducer() {
        runtimeRegistry.setFilesSidebarVisible(reducerFilesSidebarVisible)
    }

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

    func cleanupSession(for content: WorkspaceTabContent, tabId: TabID?) {
        switch content {
        case .terminal(let workspaceID, let id):
            shutdownWorkspaceTerminalSession(id: id, in: workspaceID)
        case .browser(let workspaceID, let id, _):
            removeBrowserSession(id: id, in: workspaceID)
        case .agentSession(let workspaceID, let sessionID):
            if let session = runtimeRegistry.agentSession(id: sessionID, in: workspaceID) {
                hostedContentBridge.detachAgentSession(session, workspaceID: workspaceID)
                Task {
                    await session.teardown()
                }
            }
            runtimeRegistry.removeAgentSession(id: sessionID, in: workspaceID)
        case .editor:
            if let tabId {
                removeEditorSession(tabId: tabId)
            }
        case .workflowRun(let workspaceID, let runID):
            stopWorkflowRun(workspaceID: workspaceID, runID: runID)
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
                isPreview: presentation.isPreview,
                isDirty: presentation.isDirty,
                activityIndicator: presentation.activityIndicator
            )
        }
        tabPresentationById = nextPresentationById
    }

    func currentTabPresentation(for content: WorkspaceTabContent, tabId: TabID) -> TabPresentationState {
        let (title, icon) = tabMetadata(for: content)
        let isPreview = content.workspaceID.flatMap { workspaceID in
            paneID(for: tabId, workspaceID: workspaceID)
                .flatMap { paneID in
                    store.workspaceShells[workspaceID]?.layout?.paneLayout(for: paneID)?.previewTabID
                }
        } == tabId
        return TabPresentationState(
            title: title,
            icon: icon,
            isPreview: isPreview,
            isDirty: editorSessions[tabId]?.isDirty == true,
            activityIndicator: tabActivityIndicator()
        )
    }

    func refreshRepositoryCatalog(repositoryID: Repository.ID) async {
        await refreshRepositoryCatalogs([repositoryID])
    }

    func refreshRepositoryCatalogs(_ repositoryIDs: [Repository.ID]) async {
        await store.send(.refreshRepositories(repositoryIDs)).finish()
    }

    func scheduleDeferredRepositoryRefresh(
        repositoryID: Repository.ID,
        workspaceID: Worktree.ID?,
        reason: String
    ) {
        Task { @MainActor in
            await Task.yield()

            guard selectedRepositoryID == repositoryID else { return }
            if let workspaceID,
               selectedWorkspaceID != workspaceID {
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

            guard selectedRepositoryID == repositoryID else { return }

            if let workspaceID,
               selectedWorkspaceID != workspaceID,
               let selectedWorktree = selectedCatalogWorktree {
                persistVisibleWorkspaceState()
                resetWorkspaceState()
                restoreWorkspaceState(for: selectedWorktree)
            }
        }
    }

    func markTerminalNotificationRead(_ terminalId: UUID) {
        store.send(
            .markTerminalAttentionRead(
                workspaceID: workspaceTerminalRegistry.workspaceID(for: terminalId)
                    ?? visibleWorkspaceID,
                terminalID: terminalId
            )
        )
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
        store.send(.requestRepositorySelection(repositoryID))
        guard let request = store.workspaceTransitionRequest else { return }
        store.send(.setWorkspaceTransitionRequest(nil))
        await executeWorkspaceTransition(request)
    }

    func removeRepository(_ repositoryID: Repository.ID) async {
        guard let repository = store.repositories.first(where: { $0.id == repositoryID }) else { return }

        let isActiveRepository = selectedRepositoryID == repositoryID
        if isActiveRepository {
            guard await confirmCloseCurrentRepository() else { return }
            persistVisibleWorkspaceState()
            resetWorkspaceState()
        }

        recentRepositoriesService.remove(repository.rootURL)
        store.send(.removeRepository(repositoryID))

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
        store.send(.requestWorkspaceSelection(repositoryID: repositoryID, workspaceID: workspaceID))
        guard let request = store.workspaceTransitionRequest else { return }
        store.send(.setWorkspaceTransitionRequest(nil))
        await executeWorkspaceTransition(request)
    }
}
