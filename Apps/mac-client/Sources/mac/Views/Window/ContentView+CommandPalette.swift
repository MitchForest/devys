// ContentView+CommandPalette.swift
// Palette command modeling and routing for the workspace shell.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import Foundation
import SwiftUI
import Editor
import Workspace

@MainActor
extension ContentView {
    @ViewBuilder
    func searchSheetContent(for request: WorkspaceSearchRequest) -> some View {
        switch request.mode {
        case .commands:
            ContentViewCommandPaletteSheetSurface(
                workspaceCatalog: workspaceCatalog,
                runtimeRegistry: runtimeRegistry,
                repositorySettingsStore: repositorySettingsStore,
                workspaceAttentionStore: workspaceAttentionStore,
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
        switch action {
        case .addRepository:
            requestOpenRepository()
        case .selectRepository(let repositoryID):
            Task { @MainActor in
                await selectRepository(repositoryID)
            }
        case .initializeRepository(let repositoryID):
            Task { @MainActor in
                await initializeRepository(repositoryID)
            }
        case .createWorkspace(let repositoryID):
            presentWorkspaceCreation(for: repositoryID)
        case .importWorktrees(let repositoryID):
            presentWorkspaceCreation(for: repositoryID, mode: .importedWorktree)
        case .selectWorkspace(let repositoryID, let workspaceID):
            Task { @MainActor in
                await selectWorkspace(workspaceID, in: repositoryID)
            }
        case .openAgents:
            openDefaultOrPromptAgentForSelectedWorkspace()
        case .focusAgentSession(let sessionID):
            guard let workspaceID = visibleWorkspaceID else { return }
            focusAgentSession(workspaceID: workspaceID, sessionID: sessionID)
        case .launchShell:
            openShellForSelectedWorkspace()
        case .launchClaude:
            launchClaudeForSelectedWorkspace()
        case .launchCodex:
            launchCodexForSelectedWorkspace()
        case .runDefaultProfile:
            runSelectedWorkspaceProfile()
        case .jumpToLatestUnreadWorkspace:
            Task { @MainActor in
                await jumpToLatestUnreadWorkspace()
            }
        case .revealCurrentWorkspaceInNavigator:
            revealCurrentWorkspaceInNavigator()
        }
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
        let content = TabContent.editor(workspaceID: workspaceID, url: url)
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
            await runtimeRegistry.runtimeHandle(for: workspaceID)?.fileTreeModel?.revealURL(url)
        }
    }
}
