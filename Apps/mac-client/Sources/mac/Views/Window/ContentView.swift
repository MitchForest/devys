// ContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import ComposableArchitecture
import SwiftUI
import Split
import UI
import Editor
import Git
import GhosttyTerminal
import AppKit
import Workspace
import UniformTypeIdentifiers

// MARK: - Content View

struct NavigatorRevealRequest: Equatable {
    let workspaceID: Workspace.ID
    let token: UUID

    static func == (lhs: NavigatorRevealRequest, rhs: NavigatorRevealRequest) -> Bool {
        lhs.workspaceID == rhs.workspaceID && lhs.token == rhs.token
    }
}

struct EditorOpenTraceState {
    let trace: WorkspacePerformanceTrace
    var tracker: EditorOpenPerformanceTracker
    var lastCheckpoint: WorkspacePerformanceCheckpoint?
}

struct ContentView: View {
    // MARK: - State

    let store: StoreOf<WindowFeature>

    @Environment(AppContainer.self) var container
    @Environment(AppSettings.self) var appSettings
    @Environment(RecentRepositoriesService.self) var recentRepositoriesService
    @Environment(LayoutPersistenceService.self) var layoutPersistenceService
    @Environment(RepositorySettingsStore.self) var repositorySettingsStore
    let persistentTerminalHostController = PersistentTerminalHostController()
    let terminalRelaunchPersistenceStore = TerminalRelaunchPersistenceStore()
    @State var runtimeRegistry = WorktreeRuntimeRegistry()
    @State var hostedContentBridge = HostedWorkspaceContentBridge()
    @State var themeManager = ThemeManager()
    @State var sidebarWidth: CGFloat = 240
    /// Legacy navigator width — replaced by the always-visible 48pt repo rail.
    /// Kept briefly for any residual references during migration.
    let navigatorWidth: CGFloat = Spacing.repoRailWidth
    @State var isCapsuleExpanded = false
    @State var availableRelaunchSnapshot: TerminalRelaunchSnapshot?
    @State var rehydratableHostedSessionsByID: [UUID: HostedTerminalSessionRecord] = [:]
    @State var rehydratableAttachCommandsBySessionID: [UUID: String] = [:]
    
    @State var editorSessions: [TabID: EditorSession] = [:]
    @State var editorOpenTraceStates: [TabID: EditorOpenTraceState] = [:]
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
    
    /// Computed theme from manager
    var theme: DevysTheme {
        themeManager.theme
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

    var isNavigatorCollapsed: Bool {
        store.isNavigatorCollapsed
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

    var focusedPaneId: PaneID? {
        workspaceShell?.focusedPaneID ?? workspaceLayout?.focusedFallbackPaneID
    }

    var tabContents: [TabID: WorkspaceTabContent] {
        guard let selectedWorkspaceID else { return [:] }
        return store.workspaceShells[selectedWorkspaceID]?.tabContents ?? [:]
    }

    var navigatorRevealRequest: NavigatorRevealRequest? {
        guard let request = store.navigatorRevealRequest else { return nil }
        return NavigatorRevealRequest(
            workspaceID: request.workspaceID,
            token: request.token
        )
    }

    func storedSidebarMode(for workspaceID: Workspace.ID) -> WorkspaceSidebarMode {
        store.workspaceShells[workspaceID]?.activeSidebar?.workspaceSidebarMode ?? .files
    }

    func paneLayout(for paneID: PaneID) -> WindowFeature.WorkspacePaneLayout? {
        workspaceLayout?.paneLayout(for: paneID)
    }

    func previewTabID(in paneID: PaneID) -> TabID? {
        paneLayout(for: paneID)?.previewTabID
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

    var workspaceOperationalState: WorkspaceOperationalState {
        store.operational
    }

    var hostedWorkspaceContent: HostedWorkspaceContentState {
        guard let selectedWorkspaceID else { return HostedWorkspaceContentState() }
        return store.hostedWorkspaceContentByID[selectedWorkspaceID] ?? HostedWorkspaceContentState()
    }

    var hostedAgentSessions: [HostedAgentSessionSummary] {
        hostedWorkspaceContent.agentSessions
    }

    var hostedEditorDocuments: [HostedEditorDocumentSummary] {
        hostedWorkspaceContent.editorDocuments
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
            restore.restoreAgentSessions
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: "|")
    }

    var notificationSettingsSnapshot: String {
        let notifications = appSettings.notifications
        return [
            notifications.terminalActivity,
            notifications.agentActivity
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: "|")
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
            .preferredColorScheme(themeManager.colorScheme)
            .tint(theme.accent)
            .background {
                WindowTitlebarToolbarHost(
                    theme: theme,
                    hasRepositories: store.hasRepositories,
                    hasWorktree: activeWorktree != nil,
                    isSidebarVisible: isSidebarVisible,
                    repoName: selectedRepository?.displayName,
                    branchName: selectedCatalogWorktree?.name,
                    onToggleSidebar: { toggleSidebar() },
                    onAgents: { openDefaultOrPromptAgentForSelectedWorkspace() },
                    onShell: { openShellForSelectedWorkspace() },
                    onClaude: { launchClaudeForSelectedWorkspace() },
                    onCodex: { launchCodexForSelectedWorkspace() }
                )
            }
    }

    var searchPresentationBinding: Binding<WindowFeature.SearchPresentation?> {
        Binding(
            get: { store.searchPresentation },
            set: { store.send(.setSearchPresentation($0)) }
        )
    }

    var workspaceCreationPresentationBinding: Binding<WorkspaceCreationPresentation?> {
        Binding(
            get: { store.workspaceCreationPresentation },
            set: { store.send(.setWorkspaceCreationPresentation($0)) }
        )
    }

    var agentLaunchPresentationBinding: Binding<AgentLaunchPresentation?> {
        Binding(
            get: { store.agentLaunchPresentation },
            set: { store.send(.setAgentLaunchPresentation($0)) }
        )
    }

    var gitCommitSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isGitCommitSheetPresented },
            set: { store.send(.setGitCommitSheetPresented($0)) }
        )
    }

    var createPullRequestSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isCreatePullRequestSheetPresented },
            set: { store.send(.setCreatePullRequestSheetPresented($0)) }
        )
    }

    var notificationsPanelBinding: Binding<Bool> {
        Binding(
            get: { store.isNotificationsPanelPresented },
            set: { store.send(.setNotificationsPanelPresented($0)) }
        )
    }

    func applyShellObservation<V: View>(_ view: V) -> some View {
        view
            .onChange(of: reducerFilesSidebarVisible) { _, _ in
                syncFilesSidebarVisibilityFromReducer()
            }
            .onChange(of: store.lastErrorMessage) { _, message in
                guard let message else { return }
                showLauncherUnavailableAlert(title: "Action Failed", message: message)
                store.send(.clearErrorMessage)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: FileTreeModel.itemsDeletedNotification)
            ) { notification in
                handleFileTreeDeletionNotification(notification)
            }
    }

    func applyWindowPresentations<V: View>(_ view: V) -> some View {
        applyGitPresentations(
            applySearchAndNotificationsPresentations(
                applyPrimarySheetPresentations(view)
            )
        )
    }

    func applyPrimarySheetPresentations<V: View>(_ view: V) -> some View {
        view
            .sheet(item: workspaceCreationPresentationBinding) { request in
                presentedSheetContent(
                    WorkspaceCreationSheet(
                    repository: request.repository,
                    defaults: repositorySettingsStore.settings(for: request.repository.rootURL)
                        .workspaceCreation,
                    creationService: container.workspaceCreationService,
                    initialMode: request.mode
                    ) { workspaces in
                        await handleCreatedWorkspaces(workspaces, in: request.repository)
                    }
                )
            }
            .sheet(item: agentLaunchPresentationBinding) { request in
                presentedSheetContent(
                    AgentHarnessPickerSheet(
                    onSelect: { kind in
                        store.send(.setAgentLaunchPresentation(nil))
                        if let pendingSessionID = request.pendingSessionID {
                            launchPreparedAgentSession(
                                kind,
                                workspaceID: request.workspaceID,
                                sessionID: pendingSessionID
                            )
                        } else {
                            openAgentSession(
                                kind,
                                workspaceID: request.workspaceID,
                                initialAttachments: request.initialAttachments,
                                preferredPaneID: request.preferredPaneID
                            )
                        }
                    },
                    onCancel: {
                        store.send(.setAgentLaunchPresentation(nil))
                        if let pendingSessionID = request.pendingSessionID,
                           let pendingTabID = request.pendingTabID {
                            cancelPreparedAgentSessionLaunch(
                                workspaceID: request.workspaceID,
                                sessionID: pendingSessionID,
                                tabID: pendingTabID
                            )
                        }
                    }
                    )
                )
            }
    }

    func applySearchAndNotificationsPresentations<V: View>(_ view: V) -> some View {
        view
            .sheet(item: searchPresentationBinding) { presentation in
                presentedSheetContent(searchSheetContent(for: presentation))
            }
            .sheet(isPresented: notificationsPanelBinding) {
                presentedSheetContent(notificationsPanelContent)
            }
    }

    func applyGitPresentations<V: View>(_ view: V) -> some View {
        view
            .sheet(isPresented: gitCommitSheetBinding) {
                if let gitStore {
                    presentedSheetContent(CommitSheet(store: gitStore))
                }
            }
            .sheet(isPresented: createPullRequestSheetBinding) {
                if let gitStore {
                    presentedSheetContent(
                        CreatePRSheet(store: gitStore) { _ in
                            Task { @MainActor in
                                await handleCreatedPullRequest()
                            }
                        }
                    )
                }
            }
    }

    func presentedSheetContent<V: View>(_ view: V) -> some View {
        view
            .environment(\.devysTheme, theme)
            .preferredColorScheme(themeManager.colorScheme)
    }

    static func makeSplitController() -> DevysSplitController {
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
                )
            )
        )
    }
    
    /// Create split colors from theme
    func splitColorsFromTheme(_ theme: DevysTheme) -> DevysSplitConfiguration.Colors {
        DevysSplitConfiguration.Colors(
            accent: theme.accent,
            tabBarBackground: theme.card,
            activeTabBackground: theme.base,
            inactiveText: theme.textSecondary,
            activeText: theme.text,
            separator: theme.border,
            contentBackground: theme.card,
            baseBackground: theme.base,
            paneCornerRadius: Spacing.radius,
            paneGap: Spacing.paneGap
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

private extension WindowFeature.Sidebar {
    var workspaceSidebarMode: WorkspaceSidebarMode {
        switch self {
        case .files:
            .files
        case .agents:
            .agents
        }
    }
}
