// ContentView+ObservationSurfaces.swift
// Narrow workspace shell observation surfaces.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import SwiftUI
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
struct ContentViewCommandPaletteSheetSurface: View {
    @Environment(\.dismiss) private var dismiss

    let repositories: [Repository]
    let visibleNavigatorWorkspaces: [(repositoryID: Repository.ID, workspace: Worktree)]
    let workspaceStatesByID: [Worktree.ID: WorktreeState]
    let activeWorktree: Worktree?
    let agentSessions: [HostedAgentSessionSummary]
    let workflowState: WindowFeature.WorkflowWorkspaceState
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
            workflowState: workflowState,
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
