// ContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Split
import UI
import Editor
import Git
import Syntax
import GhosttyTerminal
import AppKit
import Workspace
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    // MARK: - State
    
    @Environment(AppContainer.self) var container
    @Environment(AppSettings.self) var appSettings
    @Environment(RecentFoldersService.self) var recentFoldersService
    @Environment(LayoutPersistenceService.self) var layoutPersistenceService
    @Environment(RepositoryCommandSettingsStore.self) var commandSettingsStore
    @State var windowState = WindowState()
    @State var themeManager = ThemeManager()
    @State var activeSidebarItem: SidebarItem? = .files
    @State var sidebarWidth: CGFloat = 240
    @State var gitStore: GitStore?
    @State var worktreeManager: WorktreeManager?
    @State var worktreeInfoStore: WorktreeInfoStore?
    @State var terminalNotificationStore: TerminalNotificationStore?
    @State var runCommandStore = RunCommandStore()
    
    @State var terminalSessions: [UUID: GhosttyTerminalSession] = [:]
    @State var editorSessions: [TabID: EditorSession] = [:]
    @State var editorSessionPool = EditorSessionPool()
    
    /// Delegate for DevysSplit tab lifecycle hooks (close/save prompts)
    @State var splitDelegate = DevysSplitCloseDelegate()
    
    /// Tabs that are allowed to close without prompting (post-save flow)
    @State var closeBypass: Set<TabID> = []
    
    /// Tabs currently saving as part of a close request
    @State var closeInFlight: Set<TabID> = []
    
    // DevysSplit
    @State var controller = ContentView.makeSplitController()
    @State var tabContents: [TabID: TabContent] = [:]
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
    
    var worktreeList: [Worktree] {
        worktreeManager?.worktrees ?? []
    }

    var worktreeSelectionId: Worktree.ID? {
        worktreeManager?.selection.selectedWorktreeId
    }

    var terminalBellSnapshot: String {
        terminalSessions
            .map { "\($0.key.uuidString):\($0.value.bellCount)" }
            .sorted()
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
    }

    @ViewBuilder
    private var rootContent: some View {
        if windowState.hasFolder {
            workspaceShell
        } else {
            ProjectPickerView(
                recentFolders: Array(recentFoldersService.load().prefix(5)),
                onOpenFolder: { requestOpenFolder() },
                onOpenRecent: { url in
                    Task { @MainActor in
                        await openFolder(url)
                    }
                }
            )
        }
    }

    private func applyLifecycleModifiers<V: View>(_ view: V) -> some View {
        applyNotificationModifiers(
            applySessionModifiers(
                applyAppearanceModifiers(view)
            )
        )
    }

    private func applyAppearanceModifiers<V: View>(_ view: V) -> some View {
        view
            .onAppear {
                configureSplitDelegate()
                if !hasInitialized {
                    hasInitialized = true
                    themeManager.isDarkMode = appSettings.appearance.isDarkMode
                    themeManager.setAccentColor(from: appSettings.appearance.accentColor)
                    themeManager.applyAppearance()
                    GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
                    updateGitStore(for: windowState.folder)
                    updateWorktreeManager(for: windowState.folder)
                }
            }
            .onChange(of: themeManager.isDarkMode) { _, _ in
                themeManager.applyAppearance()
                GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
            }
            .onChange(of: appSettings.appearance.accentColor) { _, newValue in
                themeManager.setAccentColor(from: newValue)
                GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
                controller.updateColors(splitColorsFromTheme(themeManager.theme))
            }
            .onChange(of: themeManager.isDarkMode) { _, _ in
                controller.updateColors(splitColorsFromTheme(themeManager.theme))
            }
            .onChange(of: appSettings.appearance.isDarkMode) { _, newValue in
                themeManager.isDarkMode = newValue
            }
            .onChange(of: windowState.folder) { _, newFolder in
                updateGitStore(for: newFolder)
                updateWorktreeManager(for: newFolder)
            }
    }

    private func applySessionModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: worktreeList) { _, _ in
                syncWorktreeInfoStore()
            }
            .onChange(of: worktreeSelectionId) { _, newValue in
                syncWorktreeInfoSelection(newValue)
            }
            .onChange(of: terminalBellSnapshot) { _, _ in
                syncTerminalNotifications()
            }
            .onChange(of: sessionMetadataSnapshot) { _, _ in
                syncTabMetadataFromSessions()
            }
    }

    private func applyNotificationModifiers<V: View>(_ view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .devysOpenFolder)) { _ in
                requestOpenFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSave)) { _ in
                saveActiveEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSaveAs)) { _ in
                saveActiveEditorAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSaveAll)) { _ in
                Task { @MainActor in
                    _ = await EditorSessionRegistry.shared.saveAll()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSaveDefaultLayout)) { _ in
                saveDefaultLayout()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowExplorer)) { _ in
                showSidebarItem(.files)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowGit)) { _ in
                showSidebarItem(.git)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowWorktrees)) { _ in
                showSidebarItem(.files)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSelectWorktreeIndex)) { notification in
                guard let index = notification.userInfo?["index"] as? Int else { return }
                selectWorktree(at: index)
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
            // Main content area
            HStack(spacing: 0) {
                // Feature Rail (always visible)
                FeatureRail(
                    activeItem: $activeSidebarItem,
                    isDarkMode: $themeManager.isDarkMode,
                    onNewTerminal: { createTerminal() },
                    onOpenSettings: { openInPreviewTab(content: .settings) }
                )

                // Sidebar Content (file tree, etc.)
                if activeSidebarItem != nil {
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Main Workspace (DevysSplit)
                workspace
            }

            // Status bar at the bottom
            statusBar
        }
    }
}
