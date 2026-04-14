// ContentView+StatusBar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

extension ContentView {
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
