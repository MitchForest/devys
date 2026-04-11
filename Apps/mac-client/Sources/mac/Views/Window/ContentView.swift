// ContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

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

struct WorkspaceCreationPresentationRequest: Identifiable {
    let repository: Repository
    let mode: WorkspaceCreationMode

    var id: String {
        "\(repository.id)|\(mode.rawValue)"
    }
}

struct AgentLaunchPresentationRequest: Identifiable {
    let workspaceID: Workspace.ID
    let initialAttachments: [AgentAttachment]
    let preferredPaneID: PaneID?
    let pendingSessionID: AgentSessionID?
    let pendingTabID: TabID?

    var id: Workspace.ID {
        if let pendingSessionID {
            return "\(workspaceID)|\(pendingSessionID.rawValue)"
        }
        return workspaceID
    }
}

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
    
    @Environment(AppContainer.self) var container
    @Environment(AppSettings.self) var appSettings
    @Environment(RecentRepositoriesService.self) var recentRepositoriesService
    @Environment(LayoutPersistenceService.self) var layoutPersistenceService
    @Environment(RepositorySettingsStore.self) var repositorySettingsStore
    let persistentTerminalHostController = PersistentTerminalHostController()
    let terminalRelaunchPersistenceStore = TerminalRelaunchPersistenceStore()
    @State var workspaceCatalog = WindowWorkspaceCatalogStore()
    @State var runtimeRegistry = WorktreeRuntimeRegistry()
    @State var themeManager = ThemeManager()
    @State var activeSidebarItem: WorkspaceSidebarMode? = .files
    @State var isSidebarVisible: Bool = true
    @State var isNavigatorCollapsed: Bool = {
        UserDefaults.standard.bool(forKey: "com.devys.navigator.collapsed")
    }()
    @State var sidebarWidth: CGFloat = 240
    let navigatorWidth: CGFloat = DevysSpacing.navigatorDefaultWidth
    @State var workspaceTerminalRegistry = WorkspaceTerminalRegistry()
    @State var workspaceAttentionStore = WorkspaceAttentionStore()
    @State var workspaceBackgroundProcessRegistry = WorkspaceBackgroundProcessRegistry()
    @State var workspaceRunStore = WorkspaceRunStore()
    @State var workspaceCreationRequest: WorkspaceCreationPresentationRequest?
    @State var agentLaunchRequest: AgentLaunchPresentationRequest?
    @State var navigatorRevealRequest: NavigatorRevealRequest?
    @State var isCommandPalettePresented = false
    @State var isNotificationsPanelPresented = false
    @State var isGitCommitSheetPresented = false
    @State var isCreatePullRequestSheetPresented = false
    @State var availableRelaunchSnapshot: TerminalRelaunchSnapshot?
    @State var pendingTerminalRelaunchSnapshot: TerminalRelaunchSnapshot?
    @State var rehydratableHostedSessionsByID: [UUID: HostedTerminalSessionRecord] = [:]
    @State var rehydratableAttachCommandsBySessionID: [UUID: String] = [:]
    
    @State var editorSessions: [TabID: EditorSession] = [:]
    @State var editorSessionPool = EditorSessionPool()
    @State var editorOpenTraceStates: [TabID: EditorOpenTraceState] = [:]
    
    /// Delegate for DevysSplit tab lifecycle hooks (close/save prompts)
    @State var splitDelegate = DevysSplitCloseDelegate()
    
    /// Tabs that are allowed to close without prompting (post-save flow)
    @State var closeBypass: Set<TabID> = []
    
    /// Tabs currently saving as part of a close request
    @State var closeInFlight: Set<TabID> = []
    
    // DevysSplit
    @State var controller = ContentView.makeSplitController()
    @State var tabContents: [TabID: TabContent] = [:]
    @State var tabPresentationById: [TabID: TabPresentationState] = [:]
    @State var hasInitialized = false
    
    /// Currently selected/focused tab ID
    /// Updated when tabs are selected via controller.selectTab()
    @State var selectedTabId: TabID?
    
    /// Preview tab ID - only one preview tab exists at a time (VS Code behavior)
    /// Single-click opens in preview (reusable), double-click opens permanently
    @State var previewTabId: TabID?
    
    /// Computed theme from manager
    var theme: DevysTheme {
        themeManager.theme
    }
    
    var selectedCatalogWorktree: Worktree? {
        workspaceCatalog.selectedWorktree
    }

    var activeRuntime: WorktreeRuntimeHandle? {
        runtimeRegistry.activeRuntime
    }

    var activeWorktree: Worktree? {
        activeRuntime?.worktree
    }

    var visibleWorkspaceID: Workspace.ID? {
        activeRuntime?.workspaceID
    }

    var gitStore: GitStore? {
        activeRuntime?.gitStore
    }

    var activeMetadataStore: WorktreeInfoStore? {
        runtimeRegistry.metadataCoordinator.activeStore
    }

    var navigatorWorktreesByRepository: [Repository.ID: [Worktree]] {
        workspaceCatalog.worktreesByRepository
    }

    var terminalBellSnapshot: String {
        workspaceTerminalRegistry.bellSnapshot
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
        applyLifecycleModifiers(
            rootContent
                .background(theme.base)
                .environment(\.devysTheme, theme)
                .preferredColorScheme(themeManager.colorScheme)
                .tint(theme.accent)
        )
        .sheet(item: $workspaceCreationRequest) { request in
            WorkspaceCreationSheet(
                repository: request.repository,
                defaults: repositorySettingsStore.settings(for: request.repository.rootURL).workspaceCreation,
                creationService: container.workspaceCreationService,
                initialMode: request.mode
            ) { workspaces in
                await handleCreatedWorkspaces(workspaces, in: request.repository)
            }
        }
        .sheet(item: $agentLaunchRequest) { request in
            AgentHarnessPickerSheet(onSelect: { kind in
                agentLaunchRequest = nil
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
            }, onCancel: {
                agentLaunchRequest = nil
                if let pendingSessionID = request.pendingSessionID,
                   let pendingTabID = request.pendingTabID {
                    cancelPreparedAgentSessionLaunch(
                        workspaceID: request.workspaceID,
                        sessionID: pendingSessionID,
                        tabID: pendingTabID
                    )
                }
            })
        }
        .sheet(isPresented: $isCommandPalettePresented) {
            commandPaletteSheetContent
        }
        .sheet(isPresented: $isNotificationsPanelPresented) {
            notificationsPanelContent
        }
        .sheet(isPresented: $isGitCommitSheetPresented) {
            if let gitStore {
                CommitSheet(store: gitStore)
            }
        }
        .sheet(isPresented: $isCreatePullRequestSheetPresented) {
            if let gitStore {
                CreatePRSheet(store: gitStore) { _ in
                    Task { @MainActor in
                        await handleCreatedPullRequest()
                    }
                }
            }
        }
    }

}

@MainActor
extension ContentView {
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
                welcomeTabBehavior: .autoCreateAndClosePane,  // Create welcome tab, closing it closes pane
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
            tabBarBackground: theme.surface,
            activeTabBackground: theme.elevated,
            inactiveText: theme.textSecondary,
            activeText: theme.text,
            separator: theme.border,
            contentBackground: theme.base
        )
    }

    var workspaceShell: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !isNavigatorCollapsed {
                    navigatorSurface
                        .frame(width: navigatorWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

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

                VStack(spacing: 0) {
                    workspaceCanvasToolbar
                    workspace
                }
            }
            .overlay(alignment: .leading) {
                NavigatorEdgeHandle(isExpanded: !isNavigatorCollapsed) {
                    toggleNavigator()
                }
                .frame(maxHeight: .infinity, alignment: .leading)
            }

            statusBar
        }
    }
}
