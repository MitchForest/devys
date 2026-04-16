// ContentView+ObservationSurfaces.swift
// Narrow workspace shell observation surfaces.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import SwiftUI
import Split
import Editor
import Git
import GhosttyTerminal
import UI
import Workspace

@MainActor
struct ContentViewRepoRailSurface: View {
    let repositories: [Repository]
    let selectedRepositoryID: Repository.ID?
    let selectedWorkspaceID: Workspace.ID?
    let worktreesByRepository: [Repository.ID: [Worktree]]
    let workspaceStatesByID: [Worktree.ID: WorktreeState]
    let worktreeStatusHints: [Worktree.ID: StatusHint]
    let onAddRepository: () -> Void
    let onRemoveRepository: (Repository.ID) -> Void
    let onInitializeRepository: (Repository.ID) -> Void
    let onCreateWorkspace: (Repository.ID) -> Void
    let onSelectWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onReorderRepository: (Repository.ID, Int) -> Void
    let onSetRepositoryDisplayInitials: (Repository.ID, String?) -> Void
    let onSetRepositoryDisplaySymbol: (Repository.ID, String?) -> Void
    let onSetWorkspacePinned: (Repository.ID, Worktree.ID, Bool) -> Void
    let onSetWorkspaceArchived: (Repository.ID, Worktree.ID, Bool) -> Void
    let onRenameWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onDeleteWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onRevealWorkspaceInFinder: (Repository.ID, Worktree.ID) -> Void
    let onOpenWorkspaceInExternalEditor: (Repository.ID, Worktree.ID) -> Void
    let onRevealRepositoryInFinder: (Repository.ID) -> Void

    var body: some View {
        RepoRailView(
            repositories: repositories,
            selectedRepositoryID: selectedRepositoryID,
            selectedWorkspaceID: selectedWorkspaceID,
            worktreesByRepository: worktreesByRepository,
            workspaceStatesByID: workspaceStatesByID,
            worktreeStatusHints: worktreeStatusHints,
            onAddRepository: onAddRepository,
            onRemoveRepository: onRemoveRepository,
            onInitializeRepository: onInitializeRepository,
            onCreateWorkspace: onCreateWorkspace,
            onSelectWorkspace: onSelectWorkspace,
            onReorderRepository: onReorderRepository,
            onSetRepositoryDisplayInitials: onSetRepositoryDisplayInitials,
            onSetRepositoryDisplaySymbol: onSetRepositoryDisplaySymbol,
            onSetWorkspacePinned: onSetWorkspacePinned,
            onSetWorkspaceArchived: onSetWorkspaceArchived,
            onRenameWorkspace: onRenameWorkspace,
            onDeleteWorkspace: onDeleteWorkspace,
            onRevealWorkspaceInFinder: onRevealWorkspaceInFinder,
            onOpenWorkspaceInExternalEditor: onOpenWorkspaceInExternalEditor,
            onRevealRepositoryInFinder: onRevealRepositoryInFinder
        )
    }
}

@MainActor
struct ContentViewSidebarSurface: View {
    let activeSidebar: WorkspaceSidebarMode
    let selectedRepositoryRootURL: URL?
    let currentWorktree: Worktree?
    let selectedWorkspaceID: Workspace.ID?
    let fileTreeModel: FileTreeModel?
    let gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    let gitStore: GitStore?
    let changeCount: Int
    let agentSessions: [HostedAgentSessionSummary]
    let portsByWorkspaceID: [Workspace.ID: [WorkspacePort]]
    let repositorySettingsStore: RepositorySettingsStore
    let onSelectSidebar: (WorkspaceSidebarMode) -> Void
    let onPreviewFile: (Workspace.ID, URL) -> Void
    let onOpenFile: (Workspace.ID, URL) -> Void
    let onAddFileToAgent: (Workspace.ID, URL) -> Void
    let onRenameFile: (Workspace.ID, URL) -> Void
    let onDeleteFiles: (Workspace.ID, [URL]) -> Void
    let onOpenDiff: (Workspace.ID, String, Bool, Bool) -> Void
    let onAddDiffToAgent: (Workspace.ID, String, Bool) -> Void
    let onCreateAgentSession: (Workspace.ID) -> Void
    let onOpenAgentSession: (Workspace.ID, AgentSessionID) -> Void
    let onOpenPort: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onCopyPortURL: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onStopPortProcess: (WorkspacePort, Int32) -> Void

    var body: some View {
        let ports = selectedWorkspaceID.flatMap { portsByWorkspaceID[$0] } ?? []

        UnifiedWorkspaceSidebar(
            selection: activeSidebar,
            onSelect: onSelectSidebar,
            changeCount: changeCount,
            portCount: ports.count,
            agentCount: agentSessions.count
        ) {
            SidebarContentView(
                model: fileTreeModel,
                activeDirectory: currentWorktree?.workingDirectory ?? selectedRepositoryRootURL,
                gitStatusIndex: gitStatusIndex,
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
                onRenameItem: { url in
                    guard let selectedWorkspaceID else { return }
                    onRenameFile(selectedWorkspaceID, url)
                },
                onDeleteItems: { urls in
                    guard let selectedWorkspaceID else { return }
                    onDeleteFiles(selectedWorkspaceID, urls)
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
    let selectedRepositoryRootURL: URL?
    let selectedRepositoryDisplayName: String?
    let controller: DevysSplitController
    let tabContents: [TabID: WorkspaceTabContent]
    let gitStoreForContent: (WorkspaceTabContent?) -> GitStore?
    let terminalSessionForContent: (WorkspaceTabContent?) -> GhosttyTerminalSession?
    let agentSessionForContent: (WorkspaceTabContent?) -> AgentSessionRuntime?
    let agentComposerSpeechService: any AgentComposerSpeechService
    let onOpenAgentInlineTerminal: (Workspace.ID, UUID) -> Void
    let onOpenAgentFollowTarget: (Workspace.ID, AgentFollowTarget, Bool) -> Void
    let onOpenAgentDiffArtifact: (Workspace.ID, AgentDiffContent, Bool) -> Void
    let editorSessionForContent: (WorkspaceTabContent?, TabID) -> EditorSession?
    let onFocusPane: (PaneID) -> Void
    let onOpenTerminalInPane: (PaneID) -> Void
    let onOpenAgentInPane: (PaneID) -> Void
    let onOpenFileInPane: (PaneID) -> Void
    let onAttentionAcknowledged: (WorkspaceTabContent?) -> Void
    let onPresentationChange: () -> Void
    let onEditorURLChange: (TabID, URL) -> Void
    let onEditorPresentationChange: (TabID, EditorOpenPerformanceSnapshot?) -> Void

    var body: some View {
        DevysSplitView(
            controller: controller,
            content: { tab, paneId in
                let content = tabContents[tab.id]
                let gitStore = gitStoreForContent(content)
                let terminalSession = terminalSessionForContent(content)
                let agentSession = agentSessionForContent(content)
                let editorSession = editorSessionForContent(content, tab.id)
                TabContentView(
                    tab: tab,
                    content: content,
                    gitStore: gitStore,
                    terminalSession: terminalSession,
                    agentSession: agentSession,
                    agentComposerSpeechService: agentComposerSpeechService,
                    onOpenAgentInlineTerminal: onOpenAgentInlineTerminal,
                    onOpenAgentFollowTarget: onOpenAgentFollowTarget,
                    onOpenAgentDiffArtifact: onOpenAgentDiffArtifact,
                    editorSession: editorSession,
                    selectedRepositoryRootURL: selectedRepositoryRootURL,
                    selectedRepositoryDisplayName: selectedRepositoryDisplayName,
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
            emptyPane: { paneID in
                WorkspaceEmptyPaneView(
                    paneID: paneID,
                    onFocusPane: onFocusPane,
                    onOpenTerminal: onOpenTerminalInPane,
                    onOpenAgent: onOpenAgentInPane,
                    onOpenFile: onOpenFileInPane
                )
            }
        )
    }
}

@MainActor
private struct AgentSessionsSidebarSection: View {
    @Environment(\.devysTheme) private var theme

    let sessions: [HostedAgentSessionSummary]
    let onCreateSession: () -> Void
    let onOpenSession: (AgentSessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            ActionButton("New Agent Session", icon: "plus.circle.fill") {
                onCreateSession()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if sessions.isEmpty {
                Text("No active sessions in this workspace.")
                    .font(DevysTypography.caption)
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
                                .font(DevysTypography.caption.weight(.semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.tabTitle)
                                    .font(DevysTypography.body)
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)

                                Text(session.stateSummary)
                                    .font(DevysTypography.caption)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if session.tabIsBusy {
                                StatusDot(.running)
                            }
                        }
                        .padding(.horizontal, DevysSpacing.space3)
                        .padding(.vertical, 8)
                        .background(theme.card)
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                                .stroke(theme.border, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
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
struct ContentViewCommandPaletteSheetSurface: View {
    @Environment(\.dismiss) private var dismiss

    let repositories: [Repository]
    let visibleNavigatorWorkspaces: [(repositoryID: Repository.ID, workspace: Worktree)]
    let workspaceStatesByID: [Worktree.ID: WorktreeState]
    let activeWorktree: Worktree?
    let agentSessions: [HostedAgentSessionSummary]
    let repositorySettingsStore: RepositorySettingsStore
    let operationalState: WorkspaceOperationalState
    let appSettings: AppSettings
    let initialQuery: String
    let onSelect: (WorkspaceSearchItem) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0

    var body: some View {
        CommandPalette(
            query: $query,
            sections: filteredSections,
            homeSections: homeSections,
            selectedIndex: $selectedIndex,
            onSelect: selectItem(at:)
        ) {
            dismiss()
        }
        .onAppear {
            if query != initialQuery {
                query = initialQuery
            }
            resetSelection()
        }
        .onChange(of: query) { _, _ in
            resetSelection()
        }
    }

    private var catalog: ContentViewCommandPaletteCatalog {
        ContentViewCommandPaletteCatalog(
            repositories: repositories,
            visibleNavigatorWorkspaces: visibleNavigatorWorkspaces,
            workspaceStatesByID: workspaceStatesByID,
            activeWorktree: activeWorktree,
            agentSessions: agentSessions,
            repositorySettingsStore: repositorySettingsStore,
            operationalState: operationalState,
            appSettings: appSettings
        )
    }

    private var homeSections: [CommandPaletteSection] {
        catalog.homeSections
    }

    private var filteredSections: [CommandPaletteSection] {
        catalog.filteredSections(query: query)
    }

    private var visibleItems: [WorkspaceSearchItem] {
        catalog.visibleItems(query: query)
    }

    private func resetSelection() {
        selectedIndex = 0
    }

    private func selectItem(at index: Int) {
        guard visibleItems.indices.contains(index) else {
            dismiss()
            return
        }

        onSelect(visibleItems[index])
        dismiss()
    }
}

@MainActor
struct ContentViewFileSearchSheetSurface: View {
    let workspaceID: Workspace.ID?
    let fileIndex: WorkspaceFileIndex?
    let openURLs: Set<URL>
    let initialQuery: String
    let onSelect: (WorkspaceSearchItem) -> Void

    @State private var query = ""

    var body: some View {
        ContentViewSearchPaletteSurface(
            mode: .files,
            sectionTitle: "Files",
            items: items,
            isLoading: fileIndex?.isLoading == true,
            errorMessage: fileIndex == nil ? "Select a workspace to search files." : fileIndex?.lastError,
            onSelect: onSelect,
            query: $query
        )
        .onAppear {
            if query != initialQuery {
                query = initialQuery
            }
            fileIndex?.activate()
        }
        .onDisappear {
            fileIndex?.deactivate()
        }
    }

    private var items: [WorkspaceSearchItem] {
        guard let workspaceID,
              let fileIndex else {
            return []
        }

        return fileIndex.matches(for: query, openURLs: openURLs).map { result in
            WorkspaceSearchItem(
                action: .openFile(workspaceID: workspaceID, url: result.entry.fileURL),
                title: result.entry.fileName,
                subtitle: result.entry.relativePath,
                systemImage: "doc",
                keywords: [result.entry.relativePath, result.entry.fileName],
                accessory: nil
            )
        }
    }
}

@MainActor
struct ContentViewTextSearchSheetSurface: View {
    let workspaceID: Workspace.ID?
    let rootURL: URL?
    let explorerSettings: ExplorerSettings
    let initialQuery: String
    let onSelect: (WorkspaceSearchItem) -> Void

    @State private var query = ""
    @State private var service: RipgrepTextSearchService?

    var body: some View {
        ContentViewSearchPaletteSurface(
            mode: .textSearch,
            sectionTitle: "Matches",
            items: items,
            isLoading: service?.isSearching == true,
            errorMessage: serviceError,
            onSelect: onSelect,
            query: $query
        )
        .onAppear {
            if service == nil, let workspaceID, let rootURL {
                service = RipgrepTextSearchService(
                    workspaceID: workspaceID,
                    rootURL: rootURL,
                    explorerSettings: explorerSettings
                )
            }
            if query != initialQuery {
                query = initialQuery
            }
            service?.updateQuery(query)
        }
        .onChange(of: query, initial: false) { _, newValue in
            service?.updateQuery(newValue)
        }
        .onDisappear {
            service?.cancel()
        }
    }

    private var serviceError: String? {
        if workspaceID == nil || rootURL == nil {
            return "Select a workspace to search file contents."
        }
        return service?.lastError
    }

    private var items: [WorkspaceSearchItem] {
        guard let results = service?.results else { return [] }
        return results.map { match in
            WorkspaceSearchItem(
                action: .openTextSearchMatch(match),
                title: match.relativePath,
                subtitle: match.preview,
                systemImage: "magnifyingglass",
                keywords: [match.relativePath, match.preview],
                accessory: "L\(match.lineNumber):C\(match.columnNumber)"
            )
        }
    }
}

@MainActor
struct ContentViewNotificationsPanelSurface: View {
    let items: [WorkspaceNotificationPanelItem]
    let onOpen: (WorkspaceNotificationPanelItem) -> Void
    let onClear: (WorkspaceNotificationPanelItem) -> Void

    var body: some View {
        WorkspaceNotificationsPanel(
            items: items,
            onOpen: onOpen,
            onClear: onClear
        )
    }
}
