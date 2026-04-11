// ContentView+ObservationSurfaces.swift
// Narrow workspace shell observation surfaces.
//
// Copyright © 2026 Devys. All rights reserved.

// swiftlint:disable file_length
import SwiftUI
import Split
import Editor
import Git
import GhosttyTerminal
import UI
import Workspace

@MainActor
struct ContentViewNavigatorSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let workspaceAttentionStore: WorkspaceAttentionStore
    let navigatorRevealRequest: NavigatorRevealRequest?
    let onAddRepository: () -> Void
    let onMoveRepository: (Repository.ID, Int) -> Void
    let onRemoveRepository: (Repository.ID) -> Void
    let onInitializeRepository: (Repository.ID) -> Void
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
            onMoveRepository: onMoveRepository,
            onRemoveRepository: onRemoveRepository,
            onInitializeRepository: onInitializeRepository,
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
    let onAddFileToAgent: (Workspace.ID, URL) -> Void
    let onOpenDiff: (Workspace.ID, String, Bool, Bool) -> Void
    let onAddDiffToAgent: (Workspace.ID, String, Bool) -> Void
    let onCreateAgentSession: (Workspace.ID) -> Void
    let onOpenAgentSession: (Workspace.ID, AgentSessionID) -> Void
    let onOpenPort: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onCopyPortURL: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onStopPortProcess: (WorkspacePort, Int32) -> Void

    var body: some View {
        let currentRuntime = runtimeRegistry.activeRuntime
        let currentWorktree = currentRuntime?.worktree
        let selectedWorkspaceID = currentRuntime?.workspaceID
        let gitStore = currentRuntime?.gitStore
        let ports = runtimeRegistry.portCoordinator.ports(for: selectedWorkspaceID)
        let agentSessions = currentRuntime?.agentRuntimeRegistry.allSessions ?? []

        UnifiedWorkspaceSidebar(
            hasChanges: gitStore?.hasChanges ?? false,
            portCount: ports.count,
            agentCount: agentSessions.count
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
                onAddToChat: { url in
                    guard let selectedWorkspaceID else { return }
                    onAddFileToAgent(selectedWorkspaceID, url)
                },
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
                    onAddDiffToChat: { path, isStaged in
                        guard let selectedWorkspaceID else { return }
                        onAddDiffToAgent(selectedWorkspaceID, path, isStaged)
                    }
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
        } agentsContent: {
            AgentSessionsSidebarSection(
                sessions: agentSessions,
                onCreateSession: {
                    guard let selectedWorkspaceID else { return }
                    onCreateAgentSession(selectedWorkspaceID)
                },
                onOpenSession: { sessionID in
                    guard let selectedWorkspaceID else { return }
                    onOpenAgentSession(selectedWorkspaceID, sessionID)
                }
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
    let agentSessionForContent: (TabContent?) -> AgentSessionRuntime?
    let agentComposerSpeechService: any AgentComposerSpeechService
    let onOpenAgentInlineTerminal: (Workspace.ID, UUID) -> Void
    let onOpenAgentFollowTarget: (Workspace.ID, AgentFollowTarget, Bool) -> Void
    let onOpenAgentDiffArtifact: (Workspace.ID, AgentDiffContent, Bool) -> Void
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
                let agentSession = agentSessionForContent(content)
                let editorSession = editorSessionForContent(content, tab.id)
                TabContentView(
                    tab: tab,
                    content: content,
                    gitStore: runtimeRegistry.activeRuntime?.gitStore,
                    terminalSession: terminalSession,
                    agentSession: agentSession,
                    agentComposerSpeechService: agentComposerSpeechService,
                    onOpenAgentInlineTerminal: onOpenAgentInlineTerminal,
                    onOpenAgentFollowTarget: onOpenAgentFollowTarget,
                    onOpenAgentDiffArtifact: onOpenAgentDiffArtifact,
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
private struct AgentSessionsSidebarSection: View {
    @Environment(\.devysTheme) private var theme

    let sessions: [AgentSessionRuntime]
    let onCreateSession: () -> Void
    let onOpenSession: (AgentSessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Button {
                onCreateSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New Agent Session")
                        .font(DevysTypography.sm)
                    Spacer()
                }
                .foregroundStyle(theme.text)
                .padding(.horizontal, DevysSpacing.space3)
                .padding(.vertical, 8)
                .background(theme.elevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if sessions.isEmpty {
                Text("No active sessions in this workspace.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, DevysSpacing.space3)
                    .padding(.vertical, 4)
            } else {
                ForEach(sessions) { session in
                    Button {
                        onOpenSession(session.sessionID)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: session.tabIcon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.tabTitle)
                                    .font(DevysTypography.sm)
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)

                                Text(session.stateSummary)
                                    .font(DevysTypography.xs)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if session.tabIsBusy {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.horizontal, DevysSpacing.space3)
                        .padding(.vertical, 8)
                        .background(theme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.borderSubtle, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.bottom, DevysSpacing.space3)
    }
}

@MainActor
struct ContentViewToolbarSurface: View {
    let workspaceCatalog: WindowWorkspaceCatalogStore
    let runtimeRegistry: WorktreeRuntimeRegistry
    let repositorySettingsStore: RepositorySettingsStore
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void
    let onAgents: () -> Void
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
            onAgents: currentWorktree == nil ? nil : onAgents,
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
        let gitAvailable = currentRuntime?.gitStore?.isRepositoryAvailable == true

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
            onFetch: gitAvailable ? onFetch : nil,
            onPull: gitAvailable ? onPull : nil,
            onPush: gitAvailable ? onPush : nil,
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
                subtitle: "Open a local project or import a Git repository",
                systemImage: "folder.badge.plus",
                keywords: ["repository", "project", "import", "add", "open"],
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
            if repository.isGitRepository {
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
            } else {
                items.append(
                    WorkspaceCommandPaletteItem(
                        action: .initializeRepository(repository.id),
                        title: "Initialize Git in \(repository.displayName)",
                        subtitle: "Create a new Git repository for this local project",
                        systemImage: "arrow.triangle.branch",
                        keywords: ["git", "init", "initialize", repository.displayName],
                        shortcut: nil
                    )
                )
            }
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
                    action: .openAgents,
                    title: "New Agent Session",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "message.badge.waveform",
                    keywords: ["agent", "agents", "chat", "assistant", "new"],
                    shortcut: nil
                )
            )

            for session in runtimeRegistry.activeRuntime?.agentRuntimeRegistry.allSessions ?? [] {
                items.append(
                    WorkspaceCommandPaletteItem(
                        action: .focusAgentSession(session.sessionID),
                        title: "Open \(session.tabTitle)",
                        subtitle: session.stateSummary,
                        systemImage: session.tabIcon,
                        keywords: [
                            "agent",
                            "session",
                            session.tabTitle,
                            session.stateSummary
                        ],
                        shortcut: nil
                    )
                )
            }
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
