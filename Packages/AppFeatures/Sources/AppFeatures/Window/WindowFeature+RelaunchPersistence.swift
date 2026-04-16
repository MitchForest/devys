import Foundation
import Split
import Workspace

extension WindowFeature.State {
    mutating func applyWindowRelaunchRestore(
        _ request: WindowFeature.WindowRelaunchRestoreRequest
    ) {
        if request.settings.restoreWorkspaceLayoutAndTabs {
            var restoredShells: [Workspace.ID: WindowFeature.WorkspaceShell] = [:]
            for persistedState in request.snapshot.workspaceStates {
                guard worktree(for: persistedState.workspaceID) != nil else { continue }
                let restoredShell = restoredWorkspaceShell(
                    from: persistedState,
                    settings: request.settings
                )
                guard !restoredShell.tabContents.isEmpty else { continue }
                restoredShells[persistedState.workspaceID] = WindowFeature.WorkspaceShell(
                    activeSidebar: persistedState.sidebarMode.windowSidebar,
                    tabContents: restoredShell.tabContents,
                    focusedPaneID: restoredShell.focusedPaneID,
                    layout: restoredShell.layout
                )
            }
            workspaceShells = restoredShells
        }

        if let repositoryID = request.snapshot.selectedRepositoryID,
           repositories.contains(where: { $0.id == repositoryID }) {
            selectedRepositoryID = repositoryID
        }

        if request.settings.restoreSelectedWorkspace,
           let workspaceID = request.snapshot.selectedWorkspaceID,
           worktree(for: workspaceID) != nil {
            selectedWorkspaceID = workspaceID
        }

        normalizeSelection()
        restoreWorkspaceShell(for: selectedWorkspaceID)
    }

    func makeWindowRelaunchSnapshot(
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> WindowRelaunchSnapshot? {
        guard !repositories.isEmpty else { return nil }

        let workspaceStates = settings.restoreWorkspaceLayoutAndTabs
            ? collectPersistedWorkspaceLayoutStates(
                settings: settings,
                hostedTerminalSessions: hostedTerminalSessions
            )
            : []

        let snapshot = WindowRelaunchSnapshot(
            repositoryRootURLs: repositories.map(\.rootURL),
            selectedRepositoryID: selectedRepositoryID,
            selectedWorkspaceID: settings.restoreSelectedWorkspace
                ? selectedWorkspaceID
                : nil,
            hostedSessions: settings.restoreTerminalSessions
                ? hostedTerminalSessions.sorted { $0.createdAt < $1.createdAt }
                : [],
            workspaceStates: workspaceStates
        )

        return snapshot.hasRepositories ? snapshot : nil
    }
}

private extension WindowFeature.State {
    func collectPersistedWorkspaceLayoutStates(
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> [PersistedWorkspaceLayoutState] {
        let sortedWorkspaceIDs = workspaceShells.keys.sorted()
        return sortedWorkspaceIDs.compactMap { workspaceID in
            guard let shell = workspaceShells[workspaceID],
                  let layout = shell.layout else {
                return nil
            }
            return persistedWorkspaceLayoutState(
                workspaceID: workspaceID,
                activeSidebar: shell.activeSidebar ?? .files,
                layout: layout,
                tabContents: shell.tabContents,
                settings: settings,
                hostedTerminalSessions: hostedTerminalSessions
            )
        }
    }

    func persistedWorkspaceLayoutState(
        workspaceID: Workspace.ID,
        activeSidebar: WindowFeature.Sidebar,
        layout: WindowFeature.WorkspaceLayout,
        tabContents: [TabID: WorkspaceTabContent],
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> PersistedWorkspaceLayoutState? {
        guard let tree = snapshotPersistentTree(
            layout.root,
            workspaceID: workspaceID,
            tabContents: tabContents,
            settings: settings,
            hostedTerminalSessions: hostedTerminalSessions
        ) else {
            return nil
        }

        return PersistedWorkspaceLayoutState(
            workspaceID: workspaceID,
            sidebarMode: activeSidebar.persistedSidebarMode,
            tree: tree
        )
    }

    func snapshotPersistentTree(
        _ node: WindowFeature.WorkspaceLayoutNode,
        workspaceID: Workspace.ID,
        tabContents: [TabID: WorkspaceTabContent],
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> PersistedWorkspaceLayoutTree? {
        switch node {
        case .pane(let pane):
            return snapshotPersistentPane(
                pane,
                workspaceID: workspaceID,
                tabContents: tabContents,
                settings: settings,
                hostedTerminalSessions: hostedTerminalSessions
            )
        case .split(let split):
            return snapshotPersistentSplit(
                split,
                workspaceID: workspaceID,
                tabContents: tabContents,
                settings: settings,
                hostedTerminalSessions: hostedTerminalSessions
            )
        }
    }

    func snapshotPersistentPane(
        _ pane: WindowFeature.WorkspacePaneLayout,
        workspaceID: Workspace.ID,
        tabContents: [TabID: WorkspaceTabContent],
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> PersistedWorkspaceLayoutTree? {
        var tabs: [PersistedWorkspaceTabRecord] = []
        var selectedTabIndex: Int?

        for tabID in pane.tabIDs {
            guard let persistedTab = persistedTabRecord(
                for: tabID,
                workspaceID: workspaceID,
                tabContents: tabContents,
                settings: settings,
                hostedTerminalSessions: hostedTerminalSessions
            ) else {
                continue
            }

            tabs.append(persistedTab)
            if pane.selectedTabID == tabID {
                selectedTabIndex = tabs.count - 1
            }
        }

        guard !tabs.isEmpty else { return nil }
        return .pane(selectedTabIndex: selectedTabIndex, tabs: tabs)
    }

    func persistedTabRecord(
        for tabID: TabID,
        workspaceID: Workspace.ID,
        tabContents: [TabID: WorkspaceTabContent],
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> PersistedWorkspaceTabRecord? {
        guard let content = tabContents[tabID] else { return nil }

        switch content {
        case .terminal(let tabWorkspaceID, let terminalID):
            guard tabWorkspaceID == workspaceID,
                  settings.restoreTerminalSessions,
                  hostedTerminalSessions.contains(where: { record in
                      record.workspaceID == workspaceID && record.id == terminalID
                  }) else {
                return nil
            }
            return .terminal(hostedSessionID: terminalID)

        case .agentSession(let tabWorkspaceID, let sessionID):
            guard tabWorkspaceID == workspaceID,
                  settings.restoreAgentSessions,
                  let summary = hostedWorkspaceContentByID[workspaceID]?.agentSessions.first(where: {
                      $0.sessionID == sessionID
                  }),
                  summary.isRestorable else {
                return nil
            }
            return .agent(
                PersistedAgentSessionRecord(
                    sessionID: sessionID.rawValue,
                    kind: summary.kind,
                    title: summary.title,
                    subtitle: summary.subtitle
                )
            )

        case .editor(let tabWorkspaceID, let url):
            guard tabWorkspaceID == workspaceID else { return nil }
            return .editor(fileURL: url.standardizedFileURL)

        case .gitDiff(let tabWorkspaceID, let path, let isStaged):
            guard tabWorkspaceID == workspaceID else { return nil }
            return .gitDiff(path: path, isStaged: isStaged)

        case .settings:
            return nil
        }
    }

    func snapshotPersistentSplit(
        _ split: WindowFeature.WorkspaceSplitLayout,
        workspaceID: Workspace.ID,
        tabContents: [TabID: WorkspaceTabContent],
        settings: RelaunchSettingsSnapshot,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> PersistedWorkspaceLayoutTree? {
        let first = snapshotPersistentTree(
            split.first,
            workspaceID: workspaceID,
            tabContents: tabContents,
            settings: settings,
            hostedTerminalSessions: hostedTerminalSessions
        )
        let second = snapshotPersistentTree(
            split.second,
            workspaceID: workspaceID,
            tabContents: tabContents,
            settings: settings,
            hostedTerminalSessions: hostedTerminalSessions
        )

        switch (first, second) {
        case let (.some(first), .some(second)):
            return .split(
                orientation: split.orientation.rawValue,
                dividerPosition: split.dividerPosition,
                first: first,
                second: second
            )
        case let (.some(first), .none):
            return first
        case let (.none, .some(second)):
            return second
        case (.none, .none):
            return nil
        }
    }

    func restoredWorkspaceShell(
        from state: PersistedWorkspaceLayoutState,
        settings: RelaunchSettingsSnapshot
    ) -> RestoredWorkspaceShell {
        let restoredNode = restoredWorkspaceLayoutNode(
            from: state.tree,
            workspaceID: state.workspaceID,
            settings: settings
        )
        return RestoredWorkspaceShell(
            layout: WindowFeature.WorkspaceLayout(root: restoredNode.node),
            tabContents: restoredNode.tabContents,
            focusedPaneID: restoredNode.focusedPaneID ?? restoredNode.node.allPaneIDs.first
        )
    }

    func restoredWorkspaceLayoutNode(
        from tree: PersistedWorkspaceLayoutTree,
        workspaceID: Workspace.ID,
        settings: RelaunchSettingsSnapshot
    ) -> RestoredWorkspaceLayoutNode {
        switch tree {
        case .pane(let selectedTabIndex, let tabs):
            return restoredWorkspacePaneNode(
                selectedTabIndex: selectedTabIndex,
                tabs: tabs,
                workspaceID: workspaceID,
                settings: settings
            )

        case .split(let orientation, let dividerPosition, let first, let second):
            return restoredWorkspaceSplitNode(
                orientation: orientation,
                dividerPosition: dividerPosition,
                first: first,
                second: second,
                workspaceID: workspaceID,
                settings: settings
            )
        }
    }

    func restoredTabContent(
        for tab: PersistedWorkspaceTabRecord,
        workspaceID: Workspace.ID,
        settings: RelaunchSettingsSnapshot
    ) -> WorkspaceTabContent? {
        switch tab {
        case .terminal(let hostedSessionID):
            guard settings.restoreTerminalSessions else { return nil }
            return .terminal(workspaceID: workspaceID, id: hostedSessionID)
        case .agent(let record):
            guard settings.restoreAgentSessions else { return nil }
            return .agentSession(
                workspaceID: workspaceID,
                sessionID: AgentSessionID(rawValue: record.sessionID)
            )
        case .editor(let fileURL):
            return .editor(workspaceID: workspaceID, url: fileURL)
        case .gitDiff(let path, let isStaged):
            return .gitDiff(workspaceID: workspaceID, path: path, isStaged: isStaged)
        }
    }

    func restoredWorkspacePaneNode(
        selectedTabIndex: Int?,
        tabs: [PersistedWorkspaceTabRecord],
        workspaceID: Workspace.ID,
        settings: RelaunchSettingsSnapshot
    ) -> RestoredWorkspaceLayoutNode {
        let paneID = PaneID()
        var tabIDs: [TabID] = []
        var tabContents: [TabID: WorkspaceTabContent] = [:]

        for tab in tabs {
            guard let content = restoredTabContent(
                for: tab,
                workspaceID: workspaceID,
                settings: settings
            ) else {
                continue
            }
            let tabID = TabID()
            tabIDs.append(tabID)
            tabContents[tabID] = content
        }

        let selectedTabID = selectedTabIndex.flatMap { tabIDs[safe: $0] }
        return RestoredWorkspaceLayoutNode(
            node: .pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: tabIDs,
                    selectedTabID: selectedTabID
                )
            ),
            tabContents: tabContents,
            focusedPaneID: selectedTabID == nil ? nil : paneID
        )
    }

    func restoredWorkspaceSplitNode(
        orientation: String,
        dividerPosition: Double,
        first: PersistedWorkspaceLayoutTree,
        second: PersistedWorkspaceLayoutTree,
        workspaceID: Workspace.ID,
        settings: RelaunchSettingsSnapshot
    ) -> RestoredWorkspaceLayoutNode {
        let firstNode = restoredWorkspaceLayoutNode(
            from: first,
            workspaceID: workspaceID,
            settings: settings
        )
        let secondNode = restoredWorkspaceLayoutNode(
            from: second,
            workspaceID: workspaceID,
            settings: settings
        )
        let tabContents = firstNode.tabContents.merging(secondNode.tabContents) { current, _ in
            current
        }
        return RestoredWorkspaceLayoutNode(
            node: .split(
                WindowFeature.WorkspaceSplitLayout(
                    orientation: orientation == "horizontal" ? .horizontal : .vertical,
                    dividerPosition: dividerPosition,
                    first: firstNode.node,
                    second: secondNode.node
                )
            ),
            tabContents: tabContents,
            focusedPaneID: firstNode.focusedPaneID ?? secondNode.focusedPaneID
        )
    }
}

private struct RestoredWorkspaceShell {
    var layout: WindowFeature.WorkspaceLayout
    var tabContents: [TabID: WorkspaceTabContent]
    var focusedPaneID: PaneID?
}

private struct RestoredWorkspaceLayoutNode {
    var node: WindowFeature.WorkspaceLayoutNode
    var tabContents: [TabID: WorkspaceTabContent]
    var focusedPaneID: PaneID?
}

private extension WindowFeature.Sidebar {
    var persistedSidebarMode: PersistedWorkspaceSidebarMode {
        switch self {
        case .files:
            .files
        case .agents:
            .agents
        }
    }
}

private extension PersistedWorkspaceSidebarMode {
    var windowSidebar: WindowFeature.Sidebar {
        switch self {
        case .files:
            .files
        case .agents:
            .agents
        }
    }
}
