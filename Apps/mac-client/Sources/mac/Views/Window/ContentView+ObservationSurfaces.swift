// ContentView+ObservationSurfaces.swift
// Narrow workspace shell observation surfaces.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Split
import Editor
import Git
import GhosttyTerminal
import Workspace

@MainActor
struct ContentViewNavigatorSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let workspaceAttentionStore: WorkspaceAttentionStore
    let navigatorRevealRequest: NavigatorRevealRequest?
    let onAddRepository: () -> Void
    let onCreateWorkspace: (Repository.ID) -> Void
    let onSelectRepository: (Repository.ID) -> Void
    let onSelectWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onSetWorkspacePinned: (Repository.ID, Worktree.ID, Bool) -> Void
    let onSetWorkspaceArchived: (Repository.ID, Worktree.ID, Bool) -> Void
    let onRenameWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onDeleteWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onRevealWorkspaceInFinder: (Repository.ID, Worktree.ID) -> Void
    let onOpenWorkspaceInExternalEditor: (Repository.ID, Worktree.ID) -> Void

    var body: some View {
        RepositoryNavigatorView(
            repositories: workspaceCatalog.repositories,
            selectedRepositoryID: workspaceCatalog.selectedRepositoryID,
            selectedWorkspaceID: workspaceCatalog.selectedWorkspaceID,
            worktreesByRepository: workspaceCatalog.worktreesByRepository,
            revealedWorkspaceRequest: navigatorRevealRequest,
            workspaceStatesByID: workspaceCatalog.workspaceStatesByID,
            infoEntriesByWorkspaceID: runtimeRegistry.metadataCoordinator.activeStore?.entriesById ?? [:],
            attentionSummariesByWorkspaceID: workspaceAttentionStore.summariesByWorkspace,
            onAddRepository: onAddRepository,
            onCreateWorkspace: onCreateWorkspace,
            onSelectRepository: onSelectRepository,
            onSelectWorkspace: onSelectWorkspace,
            onSetWorkspacePinned: onSetWorkspacePinned,
            onSetWorkspaceArchived: onSetWorkspaceArchived,
            onRenameWorkspace: onRenameWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            onRevealWorkspaceInFinder: onRevealWorkspaceInFinder,
            onOpenWorkspaceInExternalEditor: onOpenWorkspaceInExternalEditor
        )
    }
}

@MainActor
struct ContentViewSidebarSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let repositorySettingsStore: RepositorySettingsStore
    let onPreviewFile: (Workspace.ID, URL) -> Void
    let onOpenFile: (Workspace.ID, URL) -> Void
    let onOpenDiff: (Workspace.ID, String, Bool, Bool) -> Void
    let onOpenPort: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onCopyPortURL: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onStopPortProcess: (WorkspacePort, Int32) -> Void

    var body: some View {
        let currentRuntime = runtimeRegistry.activeRuntime
        let currentWorktree = currentRuntime?.worktree
        let selectedWorkspaceID = currentRuntime?.workspaceID
        let gitStore = currentRuntime?.gitStore
        let ports = runtimeRegistry.portCoordinator.ports(for: selectedWorkspaceID)

        UnifiedWorkspaceSidebar(
            hasChanges: gitStore?.hasChanges ?? false,
            portCount: ports.count
        ) {
            SidebarContentView(
                model: currentRuntime?.fileTreeModel,
                activeDirectory: currentWorktree?.workingDirectory ?? workspaceCatalog.selectedRepositoryRootURL,
                gitStatusIndex: currentRuntime?.gitStatusIndex,
                onPreviewFile: { url in
                    guard let selectedWorkspaceID else { return }
                    onPreviewFile(selectedWorkspaceID, url)
                },
                onOpenFile: { url in
                    guard let selectedWorkspaceID else { return }
                    onOpenFile(selectedWorkspaceID, url)
                },
                onAddToChat: nil,
                showsTrailingBorder: false
            )
        } changesContent: {
            if let gitStore {
                GitSidebarView(
                    store: gitStore,
                    onPreviewDiff: { path, isStaged in
                        guard let selectedWorkspaceID else { return }
                        onOpenDiff(selectedWorkspaceID, path, isStaged, false)
                    },
                    onOpenDiff: { path, isStaged in
                        guard let selectedWorkspaceID else { return }
                        onOpenDiff(selectedWorkspaceID, path, isStaged, true)
                    },
                    onAddDiffToChat: nil
                )
            }
        } portsContent: {
            WorkspacePortsSidebarView(
                ports: ports,
                labelsByPort: repositorySettingsStore.portLabelsByPort(
                    for: currentWorktree?.repositoryRootURL
                ),
                onOpen: onOpenPort,
                onCopyURL: onCopyPortURL,
                onStopProcess: onStopPortProcess
            )
        }
    }
}

@MainActor
struct ContentViewWorkspaceSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let controller: DevysSplitController
    let tabContents: [TabID: TabContent]
    let terminalSessionForContent: (TabContent?) -> GhosttyTerminalSession?
    let editorSessionForContent: (TabContent?, TabID) -> EditorSession?
    let onFocusPane: (PaneID) -> Void
    let onAttentionAcknowledged: (TabContent?) -> Void
    let onPresentationChange: () -> Void
    let onEditorURLChange: (TabID, URL) -> Void
    let onEditorPresentationChange: (TabID, EditorOpenPerformanceSnapshot?) -> Void

    var body: some View {
        DevysSplitView(
            controller: controller,
            content: { tab, paneId in
                let content = tabContents[tab.id]
                let terminalSession = terminalSessionForContent(content)
                let editorSession = editorSessionForContent(content, tab.id)
                TabContentView(
                    tab: tab,
                    content: content,
                    gitStore: runtimeRegistry.activeRuntime?.gitStore,
                    terminalSession: terminalSession,
                    editorSession: editorSession,
                    selectedRepositoryRootURL: workspaceCatalog.selectedRepositoryRootURL,
                    selectedRepositoryDisplayName: workspaceCatalog.selectedRepository?.displayName,
                    onFocus: { onFocusPane(paneId) },
                    onAttentionAcknowledged: {
                        onAttentionAcknowledged(content)
                    },
                    onPresentationChange: onPresentationChange,
                    onEditorURLChange: { newURL in
                        onEditorURLChange(tab.id, newURL)
                    },
                    onEditorPresentationChange: { snapshot in
                        onEditorPresentationChange(tab.id, snapshot)
                    }
                )
                .id(content?.stableId ?? "empty")
            },
            emptyPane: { _ in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }
}

@MainActor
struct ContentViewToolbarSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let repositorySettingsStore: RepositorySettingsStore
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void
    let onShell: () -> Void
    let onClaude: () -> Void
    let onCodex: () -> Void
    let onRun: () -> Void
    let onOpenRepositorySettings: () -> Void

    var body: some View {
        let currentWorktree = runtimeRegistry.activeRuntime?.worktree
        let defaultStartupProfile = defaultStartupProfile(for: currentWorktree)

        WorkspaceCanvasToolbar(
            repositoryName: workspaceCatalog.selectedRepository?.displayName,
            workspaceName: currentWorktree?.name,
            isSidebarVisible: isSidebarVisible,
            onToggleSidebar: onToggleSidebar,
            onShell: currentWorktree == nil ? nil : onShell,
            onClaude: currentWorktree == nil ? nil : onClaude,
            onCodex: currentWorktree == nil ? nil : onCodex,
            onRun: defaultStartupProfile == nil ? nil : onRun,
            onOpenRepositorySettings: currentWorktree == nil ? nil : onOpenRepositorySettings,
            runDisabledReason: currentWorktree == nil
                ? "Select a workspace to launch startup profiles."
                : (defaultStartupProfile == nil
                    ? "Run will enable when this repository defines a default startup profile."
                    : nil)
        )
    }

    private func defaultStartupProfile(for worktree: Worktree?) -> StartupProfile? {
        guard let worktree else { return nil }
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        guard let defaultStartupProfileID = settings.defaultStartupProfileID else { return nil }
        return settings.startupProfiles.first { $0.id == defaultStartupProfileID }
    }
}

@MainActor
struct ContentViewStatusBarSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let repositorySettingsStore: RepositorySettingsStore
    let workspaceRunStore: WorkspaceRunStore
    let onFetch: () -> Void
    let onPull: () -> Void
    let onPush: () -> Void
    let onCommit: () -> Void
    let onCreatePR: () -> Void
    let onOpenPR: () -> Void
    let onRun: () -> Void
    let onStop: () -> Void
    let onOpenRunSettings: () -> Void
    let onToggleNavigator: () -> Void

    var body: some View {
        let currentRuntime = runtimeRegistry.activeRuntime
        let currentWorktree = currentRuntime?.worktree
        let metadataStore = runtimeRegistry.metadataCoordinator.activeStore
        let worktreeInfo = currentWorktree.flatMap { worktree in
            metadataStore?.entriesById[worktree.id]
        }
        let runState = workspaceRunStore.state(for: currentWorktree?.id)
        let defaultStartupProfile = defaultStartupProfile(for: currentWorktree)
        let portSummary = runtimeRegistry.portCoordinator.summary(for: currentWorktree?.id)

        StatusBar(
            repositoryName: workspaceCatalog.selectedRepository?.displayName,
            branchName: worktreeInfo?.branchName ?? currentWorktree?.name,
            repositoryInfo: worktreeInfo?.repositoryInfo,
            worktreeDetail: currentWorktree?.detail,
            lineChanges: worktreeInfo?.lineChanges,
            pullRequest: worktreeInfo?.pullRequest,
            prAvailability: metadataStore?.isPRAvailable,
            portSummary: portSummary,
            hasStagedChanges: (worktreeInfo?.statusSummary?.staged ?? 0) > 0,
            onFetch: currentRuntime?.gitStore == nil ? nil : onFetch,
            onPull: currentRuntime?.gitStore == nil ? nil : onPull,
            onPush: currentRuntime?.gitStore == nil ? nil : onPush,
            onCommit: (worktreeInfo?.statusSummary?.staged ?? 0) > 0 ? onCommit : nil,
            onCreatePR: metadataStore?.isPRAvailable == true ? onCreatePR : nil,
            onOpenPR: worktreeInfo?.pullRequest == nil ? nil : onOpenPR,
            runIsActive: runState?.isRunning == true,
            onRun: defaultStartupProfile == nil ? nil : onRun,
            onStop: runState?.isRunning == true ? onStop : nil,
            onOpenRunSettings: currentWorktree == nil ? nil : onOpenRunSettings,
            onToggleNavigator: onToggleNavigator
        )
    }

    private func defaultStartupProfile(for worktree: Worktree?) -> StartupProfile? {
        guard let worktree else { return nil }
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        guard let defaultStartupProfileID = settings.defaultStartupProfileID else { return nil }
        return settings.startupProfiles.first { $0.id == defaultStartupProfileID }
    }
}

@MainActor
struct ContentViewCommandPaletteSheetSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let repositorySettingsStore: RepositorySettingsStore
    let workspaceAttentionStore: WorkspaceAttentionStore
    let appSettings: AppSettings
    let onSelect: (WorkspaceCommandPaletteItem) -> Void

    var body: some View {
        WorkspaceCommandPaletteView(items: items, onSelect: onSelect)
    }

    private var items: [WorkspaceCommandPaletteItem] {
        var items: [WorkspaceCommandPaletteItem] = [
            WorkspaceCommandPaletteItem(
                action: .addRepository,
                title: "Add Repository",
                subtitle: "Import an existing Git repository into this window",
                systemImage: "folder.badge.plus",
                keywords: ["repository", "import", "add", "open"],
                shortcut: "⌘O"
            )
        ]

        for repository in workspaceCatalog.repositories {
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .selectRepository(repository.id),
                    title: "Switch to \(repository.displayName)",
                    subtitle: repository.rootURL.path,
                    systemImage: "shippingbox",
                    keywords: ["repository", "switch", repository.displayName, repository.rootURL.path],
                    shortcut: nil
                )
            )
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .createWorkspace(repository.id),
                    title: "Create Workspace in \(repository.displayName)",
                    subtitle: "New branch, existing branch, or pull request",
                    systemImage: "plus.circle",
                    keywords: ["workspace", "create", "branch", repository.displayName],
                    shortcut: nil
                )
            )
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .importWorktrees(repository.id),
                    title: "Import Worktrees in \(repository.displayName)",
                    subtitle: "Attach existing git worktrees to this repository",
                    systemImage: "square.and.arrow.down",
                    keywords: ["workspace", "worktree", "import", repository.displayName],
                    shortcut: nil
                )
            )
        }

        for entry in workspaceCatalog.visibleNavigatorWorkspaces() {
            let workspaceName = workspaceDisplayName(for: entry.workspace)
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .selectWorkspace(
                        repositoryID: entry.repositoryID,
                        workspaceID: entry.workspace.id
                    ),
                    title: "Switch to \(workspaceName)",
                    subtitle: "\(entry.workspace.name) • \(entry.workspace.workingDirectory.path)",
                    systemImage: "arrow.triangle.branch",
                    keywords: [
                        "workspace",
                        "switch",
                        entry.workspace.name,
                        workspaceName,
                        entry.workspace.workingDirectory.path
                    ],
                    shortcut: nil
                )
            )
        }

        if let activeWorktree = runtimeRegistry.activeRuntime?.worktree {
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .launchShell,
                    title: "Launch Shell",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "terminal",
                    keywords: ["shell", "terminal", "launch"],
                    shortcut: appSettings.shortcuts.binding(for: .launchShell).displayString
                )
            )
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .launchClaude,
                    title: "Launch Claude",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "sparkles",
                    keywords: ["claude", "agent", "launch"],
                    shortcut: appSettings.shortcuts.binding(for: .launchClaude).displayString
                )
            )
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .launchCodex,
                    title: "Launch Codex",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    keywords: ["codex", "agent", "launch"],
                    shortcut: appSettings.shortcuts.binding(for: .launchCodex).displayString
                )
            )
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .revealCurrentWorkspaceInNavigator,
                    title: "Reveal Current Workspace in Navigator",
                    subtitle: workspaceDisplayName(for: activeWorktree),
                    systemImage: "sidebar.left",
                    keywords: ["reveal", "navigator", "workspace", "sidebar"],
                    shortcut: nil
                )
            )

            if defaultRunProfileAvailable(for: activeWorktree) {
                items.append(
                    WorkspaceCommandPaletteItem(
                        action: .runDefaultProfile,
                        title: "Run Default Profile",
                        subtitle: activeWorktree.workingDirectory.path,
                        systemImage: "play.fill",
                        keywords: ["run", "profile", "startup"],
                        shortcut: nil
                    )
                )
            }
        }

        if workspaceAttentionStore.latestUnreadNotification() != nil {
            items.append(
                WorkspaceCommandPaletteItem(
                    action: .jumpToLatestUnreadWorkspace,
                    title: "Jump to Latest Unread Workspace",
                    subtitle: "Open the newest workspace attention item",
                    systemImage: "bell.badge",
                    keywords: ["notification", "unread", "attention", "jump"],
                    shortcut: appSettings.shortcuts.binding(for: .jumpToLatestUnreadWorkspace).displayString
                )
            )
        }

        return items
    }

    private func workspaceDisplayName(for worktree: Worktree) -> String {
        let override = workspaceCatalog.displayName(for: worktree)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            return override
        }
        return worktree.name
    }

    private func defaultRunProfileAvailable(for worktree: Worktree) -> Bool {
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        guard let defaultStartupProfileID = settings.defaultStartupProfileID else { return false }
        return settings.startupProfiles.contains { $0.id == defaultStartupProfileID }
    }
}

@MainActor
struct ContentViewNotificationsPanelSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let workspaceAttentionStore: WorkspaceAttentionStore
    let onOpen: (WorkspaceNotificationPanelItem) -> Void
    let onClear: (WorkspaceNotificationPanelItem) -> Void

    var body: some View {
        WorkspaceNotificationsPanel(
            items: items,
            onOpen: onOpen,
            onClear: onClear
        )
    }

    private var items: [WorkspaceNotificationPanelItem] {
        workspaceAttentionStore.pendingNotifications.compactMap { notification in
            guard let context = workspaceCatalog.workspaceContext(for: notification.workspaceID) else {
                return nil
            }
            return WorkspaceNotificationPanelItem(
                notification: notification,
                repositoryName: context.repository.displayName,
                workspaceName: context.worktree.name
            )
        }
    }
}
