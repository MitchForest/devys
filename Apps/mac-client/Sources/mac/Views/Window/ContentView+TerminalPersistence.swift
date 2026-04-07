// ContentView+TerminalPersistence.swift
// Devys - Persistent relaunch snapshot support for repositories, layouts, and terminals.

import Foundation
import CoreGraphics
import Split
import GhosttyTerminal
import Workspace

@MainActor
extension ContentView {
    func refreshAvailableRelaunchSnapshot() {
        guard let snapshot = terminalRelaunchPersistenceStore.load(),
              snapshot.hasRepositories else {
            availableRelaunchSnapshot = nil
            return
        }

        availableRelaunchSnapshot = snapshot
    }

    func restorePersistentTerminalRelaunchStateIfNeeded(force: Bool = false) async {
        guard workspaceCatalog.repositories.isEmpty else { return }

        refreshAvailableRelaunchSnapshot()

        guard let snapshot = availableRelaunchSnapshot else { return }
        guard force || appSettings.restore.restoreRepositoriesOnLaunch else { return }

        await restoreRelaunchSnapshot(snapshot)
    }

    func restorePreviousSession() async {
        await restorePersistentTerminalRelaunchStateIfNeeded(force: true)
    }

    func warmPersistentTerminalHostIfNeeded() async {
        guard appSettings.restore.restoreTerminalSessions else { return }
        try? await persistentTerminalHostController.ensureRunning()
    }

    func persistTerminalRelaunchSnapshotIfNeeded() {
        guard !workspaceCatalog.repositories.isEmpty else {
            clearPersistedRelaunchSnapshot()
            return
        }

        let workspaceStates = appSettings.restore.restoreWorkspaceLayoutAndTabs
            ? collectPersistedWorkspaceLayoutStates()
            : []

        let snapshot = TerminalRelaunchSnapshot(
            repositoryRootURLs: workspaceCatalog.repositories.map(\.rootURL),
            selectedRepositoryID: workspaceCatalog.selectedRepositoryID,
            selectedWorkspaceID: appSettings.restore.restoreSelectedWorkspace
                ? workspaceCatalog.selectedWorkspaceID
                : nil,
            hostedSessions: appSettings.restore.restoreTerminalSessions
                ? rehydratableHostedSessions()
                : [],
            workspaceStates: workspaceStates
        )

        guard snapshot.hasRepositories else {
            clearPersistedRelaunchSnapshot()
            return
        }

        do {
            try terminalRelaunchPersistenceStore.save(snapshot)
            availableRelaunchSnapshot = snapshot
        } catch {
            availableRelaunchSnapshot = terminalRelaunchPersistenceStore.load()
        }
    }

    func restoreWorkspaceStateFromRelaunchSnapshotIfNeeded(
        for workspaceID: Workspace.ID
    ) -> Bool {
        guard appSettings.restore.restoreWorkspaceLayoutAndTabs,
              let persistedState = pendingTerminalRelaunchSnapshot?
                .workspaceStates
                .first(where: { $0.workspaceID == workspaceID }) else {
            return false
        }

        activeSidebarItem = persistedState.sidebarMode
        controller = ContentView.makeSplitController()
        configureSplitDelegate()
        tabContents = [:]
        selectedTabId = nil
        previewTabId = nil
        closeBypass = []
        closeInFlight = []

        guard let rootPane = controller.allPaneIds.first else { return false }
        restorePersistentTree(persistedState.tree, in: rootPane, workspaceID: workspaceID)
        applyPersistedSplitRatios(from: persistedState.tree, using: controller.treeSnapshot())

        return !controller.allTabs.isEmpty
    }

    func createWorkspaceTerminalSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        id: UUID = UUID()
    ) async throws -> GhosttyTerminalSession {
        if appSettings.restore.restoreTerminalSessions {
            let record = try await persistentTerminalHostController.createSession(
                id: id,
                workspaceID: workspaceID,
                workingDirectory: workingDirectory,
                launchCommand: requestedCommand
            )
            let attachCommand = await persistentTerminalHostController.attachCommand(for: record.id)
            rehydratableHostedSessionsByID[record.id] = record
            rehydratableAttachCommandsBySessionID[record.id] = attachCommand
            syncCatalogStructure()
            return createTerminalSession(
                in: workspaceID,
                workingDirectory: workingDirectory ?? record.workingDirectory,
                stagedCommand: stagedCommand,
                attachCommand: attachCommand,
                id: record.id
            )
        }

        return createTerminalSession(
            in: workspaceID,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            id: id
        )
    }

    func shutdownWorkspaceTerminalSession(
        id: UUID,
        in workspaceID: Workspace.ID,
        terminateHostedSession: Bool = true
    ) {
        if terminateHostedSession,
           let session = workspaceTerminalRegistry.session(id: id, in: workspaceID),
           session.attachCommand != nil {
            Task {
                try? await persistentTerminalHostController.terminateSession(id: id)
            }
            rehydratableHostedSessionsByID.removeValue(forKey: id)
            rehydratableAttachCommandsBySessionID.removeValue(forKey: id)
            syncCatalogStructure()
        }

        workspaceTerminalRegistry.shutdownSession(id: id, in: workspaceID)
        workspaceAttentionStore.removeTerminal(id, in: workspaceID)
        workspaceRunStore.removeTerminal(id)
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    private func restoreRelaunchSnapshot(_ snapshot: TerminalRelaunchSnapshot) async {
        pendingTerminalRelaunchSnapshot = snapshot
        rehydratableHostedSessionsByID = [:]
        rehydratableAttachCommandsBySessionID = [:]

        if appSettings.restore.restoreTerminalSessions {
            await prepareRehydratableHostedSessions()
        }

        await openRepositories(snapshot.repositoryRootURLs.map { Repository(rootURL: $0) })

        let selectedRepositoryID = snapshot.selectedRepositoryID
        let selectedWorkspaceID = appSettings.restore.restoreSelectedWorkspace
            ? snapshot.selectedWorkspaceID
            : nil
        workspaceCatalog.restoreSelection(
            repositoryID: selectedRepositoryID,
            workspaceID: selectedWorkspaceID
        )
        if let selectedRepositoryID {
            await refreshRepositoryCatalog(repositoryID: selectedRepositoryID)
            if let selectedWorkspaceID {
                workspaceCatalog.selectWorkspace(selectedWorkspaceID, in: selectedRepositoryID)
                syncCatalogStructure()
            }
            if let selectedWorktree = selectedCatalogWorktree {
                persistVisibleWorkspaceState()
                resetWorkspaceState()
                restoreWorkspaceState(for: selectedWorktree)
            }
        } else {
            syncCatalogStructure()
        }
    }

    private func prepareRehydratableHostedSessions() async {
        do {
            let hostedSessions = try await persistentTerminalHostController.listSessions()
            rehydratableHostedSessionsByID = Dictionary(
                uniqueKeysWithValues: hostedSessions.map { ($0.id, $0) }
            )

            var attachCommandsBySessionID: [UUID: String] = [:]
            for record in hostedSessions {
                attachCommandsBySessionID[record.id] = await persistentTerminalHostController.attachCommand(
                    for: record.id
                )
            }
            rehydratableAttachCommandsBySessionID = attachCommandsBySessionID
        } catch {
            rehydratableHostedSessionsByID = [:]
            rehydratableAttachCommandsBySessionID = [:]
        }
    }

    private func clearPersistedRelaunchSnapshot() {
        try? terminalRelaunchPersistenceStore.clear()
        availableRelaunchSnapshot = nil
    }

    private func collectPersistedWorkspaceLayoutStates() -> [PersistedWorkspaceLayoutState] {
        var result: [PersistedWorkspaceLayoutState] = []

        if let visibleWorkspaceID,
           let state = persistedWorkspaceLayoutState(
                workspaceID: visibleWorkspaceID,
                sidebarMode: activeSidebarItem ?? .files,
                controller: controller,
                tabContents: tabContents
           ) {
            result.append(state)
        }

        for (workspaceID, state) in runtimeRegistry.storedShellStates where workspaceID != visibleWorkspaceID {
            if let persistedState = persistedWorkspaceLayoutState(
                workspaceID: workspaceID,
                sidebarMode: state.sidebarMode,
                controller: state.controller,
                tabContents: state.tabContents
            ) {
                result.append(persistedState)
            }
        }

        return result.sorted { $0.workspaceID < $1.workspaceID }
    }

    private func persistedWorkspaceLayoutState(
        workspaceID: Workspace.ID,
        sidebarMode: WorkspaceSidebarMode,
        controller: DevysSplitController,
        tabContents: [TabID: TabContent]
    ) -> PersistedWorkspaceLayoutState? {
        var paneIDs = ArraySlice(controller.allPaneIds)
        guard let tree = snapshotPersistentTree(
            controller.treeSnapshot(),
            workspaceID: workspaceID,
            tabContents: tabContents,
            paneIDs: &paneIDs,
            controller: controller
        ) else {
            return nil
        }

        return PersistedWorkspaceLayoutState(
            workspaceID: workspaceID,
            sidebarMode: sidebarMode,
            tree: tree
        )
    }

    private func snapshotPersistentTree(
        _ tree: ExternalTreeNode,
        workspaceID: Workspace.ID,
        tabContents: [TabID: TabContent],
        paneIDs: inout ArraySlice<PaneID>,
        controller: DevysSplitController
    ) -> PersistedWorkspaceLayoutTree? {
        switch tree {
        case .pane(let pane):
            return snapshotPersistentPane(
                pane,
                workspaceID: workspaceID,
                tabContents: tabContents,
                paneIDs: &paneIDs,
                controller: controller
            )
        case .split(let split):
            return snapshotPersistentSplit(
                split,
                workspaceID: workspaceID,
                tabContents: tabContents,
                paneIDs: &paneIDs,
                controller: controller
            )
        }
    }

    private func snapshotPersistentPane(
        _ pane: ExternalPaneNode,
        workspaceID: Workspace.ID,
        tabContents: [TabID: TabContent],
        paneIDs: inout ArraySlice<PaneID>,
        controller: DevysSplitController
    ) -> PersistedWorkspaceLayoutTree? {
        guard let paneID = paneIDs.popFirst() else { return nil }
        var tabs: [PersistedWorkspaceTabRecord] = []
        var selectedTabIndex: Int?

        for (tab, externalTab) in zip(controller.tabs(inPane: paneID), pane.tabs) {
            guard let persistedTab = persistedTabRecord(
                for: tab.id,
                workspaceID: workspaceID,
                tabContents: tabContents
            ) else {
                continue
            }

            tabs.append(persistedTab)
            if pane.selectedTabId == externalTab.id {
                selectedTabIndex = tabs.count - 1
            }
        }

        guard !tabs.isEmpty else { return nil }
        return .pane(selectedTabIndex: selectedTabIndex, tabs: tabs)
    }

    private func persistedTabRecord(
        for tabID: TabID,
        workspaceID: Workspace.ID,
        tabContents: [TabID: TabContent]
    ) -> PersistedWorkspaceTabRecord? {
        guard let content = tabContents[tabID] else { return nil }

        switch content {
        case .terminal(let tabWorkspaceID, let terminalID):
            guard tabWorkspaceID == workspaceID,
                  appSettings.restore.restoreTerminalSessions,
                  let session = workspaceTerminalRegistry.session(id: terminalID, in: workspaceID),
                  session.attachCommand != nil else {
                return nil
            }
            return .terminal(hostedSessionID: terminalID)
        case .editor(let tabWorkspaceID, let url):
            guard tabWorkspaceID == workspaceID else { return nil }
            return .editor(fileURL: canonicalEditorSessionURL(url))
        case .gitDiff(let tabWorkspaceID, let path, let isStaged):
            guard tabWorkspaceID == workspaceID else { return nil }
            return .gitDiff(path: path, isStaged: isStaged)
        case .welcome, .settings:
            return nil
        }
    }

    private func snapshotPersistentSplit(
        _ split: ExternalSplitNode,
        workspaceID: Workspace.ID,
        tabContents: [TabID: TabContent],
        paneIDs: inout ArraySlice<PaneID>,
        controller: DevysSplitController
    ) -> PersistedWorkspaceLayoutTree? {
        let first = snapshotPersistentTree(
            split.first,
            workspaceID: workspaceID,
            tabContents: tabContents,
            paneIDs: &paneIDs,
            controller: controller
        )
        let second = snapshotPersistentTree(
            split.second,
            workspaceID: workspaceID,
            tabContents: tabContents,
            paneIDs: &paneIDs,
            controller: controller
        )

        switch (first, second) {
        case let (.some(first), .some(second)):
            return .split(
                orientation: split.orientation,
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

    private func restorePersistentTree(
        _ tree: PersistedWorkspaceLayoutTree,
        in paneID: PaneID,
        workspaceID: Workspace.ID
    ) {
        switch tree {
        case .pane(let selectedTabIndex, let tabs):
            for tab in tabs {
                guard let content = restoredTabContent(for: tab, workspaceID: workspaceID) else { continue }
                _ = createTab(in: paneID, content: content)
            }

            if let selectedTabIndex,
               tabs.indices.contains(selectedTabIndex),
               let selectedTab = controller.tabs(inPane: paneID)[safe: selectedTabIndex] {
                selectTab(selectedTab.id)
            }
        case .split(let orientation, _, let first, let second):
            let splitOrientation: Split.SplitOrientation = orientation == "horizontal" ? .horizontal : .vertical
            guard let newPane = controller.splitPane(paneID, orientation: splitOrientation) else { return }
            restorePersistentTree(first, in: paneID, workspaceID: workspaceID)
            restorePersistentTree(second, in: newPane, workspaceID: workspaceID)
        }
    }

    private func restoredTabContent(
        for tab: PersistedWorkspaceTabRecord,
        workspaceID: Workspace.ID
    ) -> TabContent? {
        switch tab {
        case .terminal(let hostedSessionID):
            guard appSettings.restore.restoreTerminalSessions,
                  rehydrateHostedSession(hostedSessionID, workspaceID: workspaceID) else {
                return nil
            }
            return .terminal(workspaceID: workspaceID, id: hostedSessionID)
        case .editor(let fileURL):
            return .editor(workspaceID: workspaceID, url: fileURL)
        case .gitDiff(let path, let isStaged):
            return .gitDiff(workspaceID: workspaceID, path: path, isStaged: isStaged)
        }
    }

    private func applyPersistedSplitRatios(
        from persistedTree: PersistedWorkspaceLayoutTree,
        using currentTree: ExternalTreeNode
    ) {
        guard case .split(let orientation, let dividerPosition, let first, let second) = persistedTree,
              case .split(let currentSplit) = currentTree else {
            return
        }

        if currentSplit.orientation == orientation,
           let splitID = UUID(uuidString: currentSplit.id) {
            controller.setDividerPosition(
                CGFloat(dividerPosition),
                forSplit: splitID,
                fromExternal: true
            )
        }

        applyPersistedSplitRatios(from: first, using: currentSplit.first)
        applyPersistedSplitRatios(from: second, using: currentSplit.second)
    }

    private func rehydrateHostedSession(
        _ sessionID: UUID,
        workspaceID: Workspace.ID
    ) -> Bool {
        if workspaceTerminalRegistry.session(id: sessionID, in: workspaceID) != nil {
            return true
        }

        guard let record = rehydratableHostedSessionsByID[sessionID],
              let attachCommand = rehydratableAttachCommandsBySessionID[sessionID] else {
            return false
        }

        _ = createTerminalSession(
            in: workspaceID,
            workingDirectory: record.workingDirectory,
            attachCommand: attachCommand,
            id: sessionID
        )
        return true
    }

    private func rehydratableHostedSessions() -> [HostedTerminalSessionRecord] {
        rehydratableHostedSessionsByID.values.sorted { $0.createdAt < $1.createdAt }
    }
}

private extension DevysSplitController {
    var allTabs: [Tab] {
        allPaneIds.flatMap { tabs(inPane: $0) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
