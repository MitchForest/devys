// ContentView+CommandPalette.swift
// Palette command modeling and routing for the workspace shell.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import AppFeatures
import Foundation
import SwiftUI
import Editor
import Workspace

@MainActor
extension ContentView {
    @ViewBuilder
    func searchSheetContent(for presentation: WindowFeature.SearchPresentation) -> some View {
        searchSheetContent(
            for: WorkspaceSearchRequest(
                mode: presentation.mode.workspaceSearchMode,
                initialQuery: presentation.initialQuery,
                token: presentation.id
            )
        )
    }

    @ViewBuilder
    func searchSheetContent(for request: WorkspaceSearchRequest) -> some View {
        switch request.mode {
        case .commands:
            ContentViewCommandPaletteSheetSurface(
                repositories: store.repositories,
                visibleNavigatorWorkspaces: visibleNavigatorWorkspaces,
                workspaceStatesByID: store.workspaceStatesByID,
                activeWorktree: activeWorktree,
                chatSessions: hostedChatSessions,
                workflowState: visibleWorkspaceID.map { workflowWorkspaceState(for: $0) }
                    ?? WindowFeature.WorkflowWorkspaceState(),
                repositorySettingsStore: repositorySettingsStore,
                operationalState: workspaceOperationalState,
                appSettings: appSettings,
                initialQuery: request.initialQuery,
                onSelect: performSearchAction
            )
        case .files:
            ContentViewFileSearchSheetSurface(
                workspaceID: visibleWorkspaceID,
                fileIndex: activeWorktree.map { container.makeWorkspaceFileIndex(rootURL: $0.workingDirectory) },
                openURLs: Set(editorSessions.values.map(\.url)),
                initialQuery: request.initialQuery,
                onSelect: performSearchAction
            )
        case .textSearch:
            ContentViewTextSearchSheetSurface(
                workspaceID: visibleWorkspaceID,
                rootURL: activeWorktree?.workingDirectory,
                explorerSettings: appSettings.explorer,
                initialQuery: request.initialQuery,
                onSelect: performSearchAction
            )
        }
    }

    func performSearchAction(_ item: WorkspaceSearchItem) {
        switch item.action {
        case .command(let command):
            performCommandPaletteAction(command)
        case .openFile(let workspaceID, let url):
            openEditorSearchResult(
                workspaceID: workspaceID,
                url: url,
                navigationTarget: nil
            )
        case .openTextSearchMatch(let match):
            openEditorSearchResult(
                workspaceID: match.workspaceID,
                url: match.fileURL,
                navigationTarget: .match(match.match)
            )
        }
    }

    func performCommandPaletteAction(_ action: WorkspaceCommandPaletteAction) {
        if handleProjectPaletteAction(action)
            || handleNavigationPaletteAction(action)
            || handleAgentPaletteAction(action)
            || handleWorkflowPaletteAction(action)
            || handleExecutionPaletteAction(action)
            || handleAttentionPaletteAction(action) {
            return
        }
    }

    private func handleProjectPaletteAction(
        _ action: WorkspaceCommandPaletteAction
    ) -> Bool {
        switch action {
        case .addRepository:
            store.send(.requestAddRepository)
        case .initializeRepository(let repositoryID):
            store.send(.requestInitializeRepository(repositoryID))
        case .createWorkspace(let repositoryID):
            store.send(.presentWorkspaceCreation(repositoryID: repositoryID, mode: .newBranch))
        case .importWorktrees(let repositoryID):
            store.send(.presentWorkspaceCreation(repositoryID: repositoryID, mode: .importedWorktree))
        default:
            return false
        }
        return true
    }

    private func handleNavigationPaletteAction(
        _ action: WorkspaceCommandPaletteAction
    ) -> Bool {
        switch action {
        case .selectRepository(let repositoryID):
            store.send(.requestRepositorySelection(repositoryID))
        case .selectWorkspace(let repositoryID, let workspaceID):
            store.send(.requestWorkspaceSelection(repositoryID: repositoryID, workspaceID: workspaceID))
        case .revealCurrentWorkspaceInNavigator:
            store.send(.revealCurrentWorkspaceInNavigator)
        default:
            return false
        }
        return true
    }

    private func handleAgentPaletteAction(
        _ action: WorkspaceCommandPaletteAction
    ) -> Bool {
        switch action {
        case .openChat:
            store.send(.requestWorkspaceCommand(.openChat))
        case .focusChatSession(let sessionID):
            store.send(.requestFocusChatSession(sessionID))
        default:
            return false
        }
        return true
    }

    private func handleWorkflowPaletteAction(
        _ action: WorkspaceCommandPaletteAction
    ) -> Bool {
        guard let workspaceID = visibleWorkspaceID else { return false }
        switch action {
        case .createWorkflow:
            createWorkflowDefinition(in: workspaceID)
        case .openWorkflowDefinition(let definitionID):
            openWorkflowDefinition(workspaceID: workspaceID, definitionID: definitionID)
        case .openWorkflowRun(let runID):
            openInPermanentTab(content: .workflowRun(workspaceID: workspaceID, runID: runID))
        default:
            return false
        }
        return true
    }

    private func handleExecutionPaletteAction(
        _ action: WorkspaceCommandPaletteAction
    ) -> Bool {
        switch action {
        case .launchShell:
            store.send(.requestWorkspaceCommand(.launchShell))
        case .launchClaude:
            store.send(.requestWorkspaceCommand(.launchClaude))
        case .launchCodex:
            store.send(.requestWorkspaceCommand(.launchCodex))
        case .runDefaultProfile:
            store.send(.requestWorkspaceCommand(.runWorkspaceProfile))
        default:
            return false
        }
        return true
    }

    private func handleAttentionPaletteAction(
        _ action: WorkspaceCommandPaletteAction
    ) -> Bool {
        switch action {
        case .jumpToLatestUnreadWorkspace:
            store.send(.requestWorkspaceCommand(.jumpToLatestUnreadWorkspace))
        default:
            return false
        }
        return true
    }

    func showFindInActiveEditor() {
        guard let selectedTabId,
              let session = editorSessions[selectedTabId] else {
            NSSound.beep()
            return
        }

        session.presentFind()
    }

    func openEditorSearchResult(
        workspaceID: Workspace.ID,
        url: URL,
        navigationTarget: EditorNavigationTarget?
    ) {
        let content = WorkspaceTabContent.editor(workspaceID: workspaceID, url: url)
        openInPermanentTab(content: content)

        if let tabId = findExistingTab(for: content),
           let session = editorSessions[tabId] {
            if let navigationTarget {
                session.navigate(to: navigationTarget)
            } else {
                session.requestKeyboardFocus()
            }
        }

        Task { @MainActor in
            await runtimeRegistry.fileTreeModel(for: workspaceID)?.revealURL(url)
        }
    }
}

private extension WindowFeature.SearchMode {
    var workspaceSearchMode: WorkspaceSearchMode {
        switch self {
        case .commands:
            .commands
        case .files:
            .files
        case .textSearch:
            .textSearch
        }
    }
}
