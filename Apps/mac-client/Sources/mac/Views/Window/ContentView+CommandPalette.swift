// ContentView+CommandPalette.swift
// Palette command modeling and routing for the workspace shell.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import SwiftUI
import Workspace

@MainActor
extension ContentView {
    var commandPaletteSheetContent: some View {
        ContentViewCommandPaletteSheetSurface(
            workspaceCatalog: workspaceCatalog,
            runtimeRegistry: runtimeRegistry,
            repositorySettingsStore: repositorySettingsStore,
            workspaceAttentionStore: workspaceAttentionStore,
            appSettings: appSettings,
            onSelect: performCommandPaletteAction
        )
    }

    func performCommandPaletteAction(_ item: WorkspaceCommandPaletteItem) {
        switch item.action {
        case .addRepository:
            requestOpenRepository()
        case .selectRepository(let repositoryID):
            Task { @MainActor in
                await selectRepository(repositoryID)
            }
        case .createWorkspace(let repositoryID):
            presentWorkspaceCreation(for: repositoryID)
        case .importWorktrees(let repositoryID):
            presentWorkspaceCreation(for: repositoryID, mode: .importedWorktree)
        case .selectWorkspace(let repositoryID, let workspaceID):
            Task { @MainActor in
                await selectWorkspace(workspaceID, in: repositoryID)
            }
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
}
