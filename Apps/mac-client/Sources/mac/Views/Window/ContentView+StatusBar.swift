// ContentView+StatusBar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace

extension ContentView {
    var workspaceCanvasToolbar: some View {
        ContentViewToolbarSurface(
            workspaceCatalog: workspaceCatalog,
            runtimeRegistry: runtimeRegistry,
            repositorySettingsStore: repositorySettingsStore,
            isSidebarVisible: isSidebarVisible,
            onToggleSidebar: toggleSidebar,
            onShell: { openShellForSelectedWorkspace() },
            onClaude: { launchClaudeForSelectedWorkspace() },
            onCodex: { launchCodexForSelectedWorkspace() },
            onRun: { runSelectedWorkspaceProfile() },
            onOpenRepositorySettings: { openRepositorySettings() }
        )
    }

    var statusBar: some View {
        ContentViewStatusBarSurface(
            workspaceCatalog: workspaceCatalog,
            runtimeRegistry: runtimeRegistry,
            repositorySettingsStore: repositorySettingsStore,
            workspaceRunStore: workspaceRunStore,
            onFetch: { fetchSelectedWorkspaceRemote() },
            onPull: { pullSelectedWorkspaceRemote() },
            onPush: { pushSelectedWorkspaceRemote() },
            onCommit: { commitSelectedWorkspaceChanges() },
            onCreatePR: { createPullRequestForSelectedWorkspace() },
            onOpenPR: { openSelectedWorkspacePullRequest() },
            onRun: { runSelectedWorkspaceProfile() },
            onStop: { stopSelectedWorkspaceProfile() },
            onOpenRunSettings: { editSelectedWorkspaceProfiles() },
            onToggleNavigator: { toggleNavigator() }
        )
    }
}
