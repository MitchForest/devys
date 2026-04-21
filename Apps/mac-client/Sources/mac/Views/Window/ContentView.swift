// ContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import AppKit
import ComposableArchitecture
import Editor
import Git
import GhosttyTerminal
import RemoteCore
import Split
import SwiftUI
import UI
import Workspace
import UniformTypeIdentifiers

struct EditorOpenTraceState {
    let trace: WorkspacePerformanceTrace
    var tracker: EditorOpenPerformanceTracker
    var lastCheckpoint: WorkspacePerformanceCheckpoint?
}

struct TerminalOpenTraceState {
    let trace: WorkspacePerformanceTrace
    var tracker: TerminalOpenPerformanceTracker
    var lastCheckpoint: WorkspacePerformanceCheckpoint?
}

struct ContentView: View {
    // MARK: - State

    let store: StoreOf<WindowFeature>

    @Environment(\.colorScheme) var systemColorScheme
    @Environment(AppContainer.self) var container
    @Environment(AppSettings.self) var appSettings
    @Environment(RecentRepositoriesService.self) var recentRepositoriesService
    @Environment(LayoutPersistenceService.self) var layoutPersistenceService
    @Environment(RepositorySettingsStore.self) var repositorySettingsStore
    let persistentTerminalHostController = PersistentTerminalHostController()
    let terminalRelaunchPersistenceStore = TerminalRelaunchPersistenceStore()
    @State var runtimeRegistry = WorktreeRuntimeRegistry()
    @State var hostedContentBridge = HostedWorkspaceContentBridge()
    @State var browserRegistry = WorkspaceBrowserRegistry()
    @State var themeManager = ThemeManager()
    @State var sidebarWidth: CGFloat = 240
    @State var isCapsuleExpanded = false
    @State var availableRelaunchSnapshot: TerminalRelaunchSnapshot?
    @State var rehydratableHostedSessionsByID: [UUID: HostedTerminalSessionRecord] = [:]
    @State var terminalHostWarmupState = TerminalHostWarmupState()
    @State var terminalRendererWarmupState = TerminalRendererWarmupState()
    
    @State var editorSessions: [TabID: EditorSession] = [:]
    @State var editorOpenTraceStates: [TabID: EditorOpenTraceState] = [:]
    @State var terminalOpenTraceStates: [UUID: TerminalOpenTraceState] = [:]
    @State var workspaceViewStatesByID: [Workspace.ID: WorkspaceViewState] = [:]
    
    /// Delegate for DevysSplit tab lifecycle hooks (close/save prompts)
    @State var splitDelegate = DevysSplitCloseDelegate()
    
    /// Tabs that are allowed to close without prompting (post-save flow)
    @State var closeBypass: Set<TabID> = []
    
    /// Tabs currently saving as part of a close request
    @State var closeInFlight: Set<TabID> = []
    
    // DevysSplit
    @State var controller = ContentView.makeSplitController()
    @State var tabPresentationById: [TabID: TabPresentationState] = [:]
    @State var hasInitialized = false

    @State var workflowRunTerminalPaneMap: [UUID: PaneID] = [:]
    @State var openedWorkflowTerminalIDs: Set<UUID> = []
    
    /// Computed theme from manager
    var theme: DevysTheme {
        themeManager.theme(systemColorScheme: systemColorScheme)
    }

    init(
        store: StoreOf<WindowFeature>,
        initialAppearance: AppearanceSettings = AppearanceSettings()
    ) {
        self.store = store

        let initialAccentColor = ThemeManager.accentColor(from: initialAppearance.accentColor)
        _themeManager = State(
            initialValue: ThemeManager(
                appearanceMode: initialAppearance.mode,
                accentColor: initialAccentColor
            )
        )
        _controller = State(
            initialValue: Self.makeSplitController(
                colors: Self.makeSplitColors(
                    from: ThemeManager.bootstrapTheme(
                        appearanceMode: initialAppearance.mode,
                        accentColor: initialAccentColor
                    )
                )
            )
        )
    }

    var activeSidebarItem: WorkspaceSidebarMode? {
        store.activeSidebar?.workspaceSidebarMode
    }

    var workspaceOperationalController: WorkspaceOperationalController {
        container.workspaceOperationalController
    }

    var workspaceTerminalRegistry: WorkspaceTerminalRegistry {
        workspaceOperationalController.terminalRegistry
    }

    var workspaceBackgroundProcessRegistry: WorkspaceBackgroundProcessRegistry {
        workspaceOperationalController.backgroundProcessRegistry
    }

    var editorSessionRegistry: EditorSessionRegistry {
        container.editorSessionRegistry
    }

    var reducerFilesSidebarVisible: Bool {
        isSidebarVisible && activeSidebarItem == .files
    }

    var isSidebarVisible: Bool {
        store.isSidebarVisible
    }

    var selectedTabId: TabID? {
        store.selectedTabID
    }

    var workspaceShell: WindowFeature.WorkspaceShell? {
        guard let selectedWorkspaceID else { return nil }
        return store.workspaceShells[selectedWorkspaceID]
    }

    var workspaceLayout: WindowFeature.WorkspaceLayout? {
        workspaceShell?.layout
    }

    var tabContents: [TabID: WorkspaceTabContent] {
        guard let selectedWorkspaceID else { return [:] }
        return store.workspaceShells[selectedWorkspaceID]?.tabContents ?? [:]
    }

    func paneLayout(for paneID: PaneID) -> WindowFeature.WorkspacePaneLayout? {
        workspaceLayout?.paneLayout(for: paneID)
    }

    func paneID(for tabID: TabID, workspaceID: Workspace.ID? = nil) -> PaneID? {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID,
              let layout = store.workspaceShells[workspaceID]?.layout else {
            return nil
        }
        return layout.allPaneIDs.first { paneID in
            layout.paneLayout(for: paneID)?.tabIDs.contains(tabID) == true
        }
    }

    var selectedRepositoryID: Repository.ID? {
        store.selectedRepositoryID
    }

    var selectedWorkspaceID: Workspace.ID? {
        store.selectedWorkspaceID
    }

    var selectedRepository: Repository? {
        store.selectedRepository
    }

    var selectedRepositoryRootURL: URL? {
        selectedRepository?.rootURL
    }

    var selectedRemoteRepository: RemoteRepositoryAuthority? {
        store.selectedRemoteRepository
    }

    var selectedRemoteWorktree: RemoteWorktree? {
        store.selectedRemoteWorktree
    }

    var isRemoteWorkspaceSelected: Bool {
        selectedRemoteWorktree != nil
    }

    var selectedCatalogWorktree: Worktree? {
        guard let selectedRepositoryID,
              let selectedWorkspaceID else {
            return nil
        }
        return store.worktreesByRepository[selectedRepositoryID]?
            .first { $0.id == selectedWorkspaceID }
    }

    var activeWorktree: Worktree? {
        runtimeRegistry.activeWorktree
    }

    var hasLaunchableWorkspace: Bool {
        selectedCatalogWorktree != nil || selectedRemoteWorktree != nil
    }

    var currentBreadcrumbRepositoryName: String? {
        selectedRepository?.displayName ?? selectedRemoteRepository?.railDisplayName
    }

    var currentBreadcrumbBranchName: String? {
        selectedCatalogWorktree?.name ?? selectedRemoteWorktree?.branchName
    }

    var workspaceOperationalState: WorkspaceOperationalState {
        store.operational
    }

    var hostedWorkspaceContent: HostedWorkspaceContentState {
        guard let selectedWorkspaceID else { return HostedWorkspaceContentState() }
        return store.hostedWorkspaceContentByID[selectedWorkspaceID] ?? HostedWorkspaceContentState()
    }

    var hostedChatSessions: [HostedChatSessionSummary] {
        hostedWorkspaceContent.chatSessions
    }

    var visibleWorkspaceID: Workspace.ID? {
        runtimeRegistry.activeWorkspaceID
    }

    var gitStore: GitStore? {
        guard let workspaceID = visibleWorkspaceID else { return nil }
        return runtimeRegistry.gitStore(for: workspaceID)
    }

    func editorSessionPool(for workspaceID: Workspace.ID?) -> EditorSessionPool? {
        guard let workspaceID else { return nil }
        return runtimeRegistry.editorSessionPool(for: workspaceID)
    }

    var navigatorWorktreesByRepository: [Repository.ID: [Worktree]] {
        store.worktreesByRepository
    }

    var restoreSettingsSnapshot: String {
        let restore = appSettings.restore
        return [
            restore.restoreRepositoriesOnLaunch,
            restore.restoreSelectedWorkspace,
            restore.restoreWorkspaceLayoutAndTabs,
            restore.restoreTerminalSessions,
            restore.restoreChatSessions
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: "|")
    }

    var notificationSettingsSnapshot: String {
        let notifications = appSettings.notifications
        return [
            notifications.terminalActivity,
            notifications.chatActivity
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: "|")
    }

    var remoteRepositorySnapshot: String {
        store.remoteRepositories.map(\.id).joined(separator: "|")
    }

    var reviewHookSyncSnapshot: String {
        store.repositories
            .map { repository in
                let settings = repositorySettingsStore.settings(for: repository.rootURL)
                return [
                    repository.rootURL.standardizedFileURL.path,
                    settings.review.isEnabled ? "1" : "0",
                    settings.review.reviewOnCommit ? "1" : "0"
                ]
                .joined(separator: "|")
            }
            .sorted()
            .joined(separator: "||")
    }
    
    // MARK: - Body
    
    var body: some View {
        let lifecycleContent = applyLifecycleModifiers(themedRootContent)
        let observedContent = applyShellObservation(lifecycleContent)
        return applyWindowPresentations(observedContent)
    }
}

@MainActor
extension ContentView {
    var themedRootContent: some View {
        rootContent
            .background(theme.base)
            .environment(\.devysTheme, theme)
            .preferredColorScheme(themeManager.preferredColorScheme)
            .tint(theme.accent)
            .background {
                WindowTitlebarToolbarHost(
                    theme: theme,
                    hasRepositories: store.hasRepositories,
                    hasWorktree: hasLaunchableWorkspace,
                    supportsStructuredWorkspaceFeatures: !isRemoteWorkspaceSelected && activeWorktree != nil,
                    isSidebarVisible: isSidebarVisible,
                    repoName: currentBreadcrumbRepositoryName,
                    branchName: currentBreadcrumbBranchName,
                    onToggleSidebar: { toggleSidebar() },
                    onWorkflow: {
                        guard !isRemoteWorkspaceSelected else { return }
                        guard let workspaceID = visibleWorkspaceID else { return }
                        createWorkflowDefinition(in: workspaceID)
                    },
                    onAgents: {
                        guard !isRemoteWorkspaceSelected else { return }
                        openDefaultOrPromptChatForSelectedWorkspace()
                    },
                    onShell: { openShellForSelectedWorkspace() },
                    onClaude: { launchClaudeForSelectedWorkspace() },
                    onCodex: { launchCodexForSelectedWorkspace() }
                )
            }
    }

    func applyShellObservation<V: View>(_ view: V) -> some View {
        view
            .onAppear {
                syncVisibleWorkspaceRuntimeWithReducerSelection()
            }
            .onChange(of: workspaceRuntimeSyncSnapshot) { _, _ in
                syncVisibleWorkspaceRuntimeWithReducerSelection()
            }
            .onChange(of: reducerFilesSidebarVisible) { _, _ in
                syncFilesSidebarVisibilityFromReducer()
            }
            .onChange(of: store.lastErrorMessage) { _, message in
                guard let message else { return }
                showLauncherUnavailableAlert(title: "Action Failed", message: message)
                store.send(.clearErrorMessage)
            }
            .onChange(of: remoteRepositorySnapshot) { _, _ in
                for repository in store.remoteRepositories
                where (store.remoteWorktreesByRepository[repository.id] ?? []).isEmpty {
                    refreshRemoteRepository(repository.id)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: FileTreeModel.itemsDeletedNotification)
            ) { notification in
                handleFileTreeDeletionNotification(notification)
            }
    }

    static func makeSplitController(
        colors: DevysSplitConfiguration.Colors = DevysSplitConfiguration.Colors()
    ) -> DevysSplitController {
        DevysSplitController(
            configuration: DevysSplitConfiguration(
                allowSplits: true,
                allowCloseTabs: true,
                allowCloseLastPane: false,
                allowTabReordering: true,
                allowCrossPaneTabMove: true,
                autoCloseEmptyPanes: true,  // Auto-close empty panes
                contentViewLifecycle: .keepAllAlive,
                newTabPosition: .current,
                acceptedDropTypes: [.fileURL, .devysGitDiff],
                appearance: .init(
                    tabBarHeight: 36,
                    tabMinWidth: 100,
                    tabMaxWidth: 200,
                    tabSpacing: 0,
                    minimumPaneWidth: 200,
                    minimumPaneHeight: 150,
                    showSplitButtons: true
                ),
                colors: colors
            )
        )
    }
    
    var workspaceShellView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Repo rail — always visible, slim 48pt strip
                repoRailSurface

                if isSidebarVisible {
                    sidebarContent
                        .frame(width: sidebarWidth)

                    SidebarResizeHandle(
                        width: $sidebarWidth,
                        minWidth: DevysSpacing.sidebarMinWidth,
                        maxWidth: DevysSpacing.sidebarMaxWidth,
                        persistenceKey: "com.devys.sidebar.width"
                    )
                }

                workspace
                    .overlay(alignment: .bottom) {
                        // Keep the floating status capsule centered in the workspace region,
                        // not the full window shell that includes the rail and sidebar.
                        statusCapsuleOverlay
                            .padding(.bottom, DevysSpacing.space2)
                    }
            }
        }
    }
}
