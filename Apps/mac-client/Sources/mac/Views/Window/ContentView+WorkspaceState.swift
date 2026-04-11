// ContentView+WorkspaceState.swift
// Devys - Workspace-owned shell runtime swapping.

import Foundation
import Workspace

@MainActor
extension ContentView {
    private func makeWorkspaceShellStateSnapshot(_ workspaceID: Workspace.ID) -> WorkspaceShellState {
        WorkspaceShellState(
            workspaceID: workspaceID,
            sidebarMode: activeSidebarItem ?? .files,
            gitStore: gitStore,
            agentRuntimeRegistry: activeRuntime?.agentRuntimeRegistry ?? WorkspaceAgentRuntimeRegistry(),
            editorSessions: editorSessions,
            editorSessionPool: editorSessionPool,
            controller: controller,
            tabContents: tabContents,
            selectedTabId: selectedTabId,
            previewTabId: previewTabId,
            closeBypass: closeBypass,
            closeInFlight: closeInFlight
        )
    }

    func persistVisibleWorkspaceState() {
        guard let visibleWorkspaceID else { return }
        runtimeRegistry.persistShellState(makeWorkspaceShellStateSnapshot(visibleWorkspaceID))
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    func restoreWorkspaceState(for worktree: Worktree) {
        let workspaceID = worktree.id
        let hadSavedState = runtimeRegistry.containsRuntime(for: workspaceID)
        let trace = WorkspacePerformanceRecorder.begin(
            "workspace-restore",
            context: [
                "workspace_id": workspaceID,
                "has_saved_state": hadSavedState ? "1" : "0"
            ]
        )
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }

        let state = runtimeRegistry.shellState(for: worktree)

        activeSidebarItem = state.sidebarMode
        editorSessions = state.editorSessions
        editorSessionPool = state.editorSessionPool
        controller = state.controller
        tabContents = state.tabContents
        selectedTabId = state.selectedTabId
        previewTabId = state.previewTabId
        closeBypass = state.closeBypass
        closeInFlight = state.closeInFlight

        if !hadSavedState {
            if !restoreWorkspaceStateFromRelaunchSnapshotIfNeeded(for: workspaceID) {
                controller = ContentView.makeSplitController()
                applyDefaultLayout()
                controller.populateEmptyPanesWithWelcomeTabs()
            }
            runtimeRegistry.persistShellState(makeWorkspaceShellStateSnapshot(workspaceID))
        }

        runtimeRegistry.activate(
            worktree: worktree,
            filesSidebarVisible: activeSidebarItem == .files
        )
        bindRepositoryCapability(for: worktree)

        configureSplitDelegate()
        syncTabMetadataFromSessions()
        Task { @MainActor in
            await Task.yield()
            await runtimeRegistry.hydrateGitRuntimeIfNeeded(for: worktree.id)
        }
        if let selectedTabId,
           case .terminal(_, let terminalID) = tabContents[selectedTabId] {
            markTerminalNotificationRead(terminalID)
        }
    }

    func discardWorkspaceState(_ workspaceID: Workspace.ID) {
        let wasVisibleWorkspace = visibleWorkspaceID == workspaceID
        runtimeRegistry.portCoordinator.clearWorkspace(workspaceID)
        runtimeRegistry.discardWorkspace(workspaceID) { state in
            disposeWorkspaceState(state)
        }

        workspaceAttentionStore.clearWorkspace(workspaceID)
        if wasVisibleWorkspace {
            resetWorkspaceState()
        }
    }

    private func disposeWorkspaceState(_ state: WorkspaceShellState) {
        for terminalID in workspaceTerminalRegistry.sessions(for: state.workspaceID).keys {
            shutdownWorkspaceTerminalSession(
                id: terminalID,
                in: state.workspaceID,
                terminateHostedSession: true
            )
        }
        workspaceBackgroundProcessRegistry.shutdownAll(in: state.workspaceID)
        syncCatalogStructure()
        workspaceRunStore.clearWorktree(state.workspaceID)
        for session in state.agentRuntimeRegistry.allSessions {
            Task {
                await session.teardown()
            }
        }
        state.agentRuntimeRegistry.removeAll()

        for tabID in state.editorSessions.keys {
            if let session = state.editorSessions[tabID] {
                state.editorSessionPool.release(url: session.url)
            }
            EditorSessionRegistry.shared.unregister(tabId: tabID)
        }
    }

    private func bindRepositoryCapability(for worktree: Worktree) {
        guard let gitStore = runtimeRegistry.runtimeHandle(for: worktree.id)?.gitStore else { return }
        gitStore.onRepositoryAvailabilityDidUpdate = { [weak workspaceCatalog, weak runtimeRegistry] isAvailable in
            Task { @MainActor in
                workspaceCatalog?.setRepositorySourceControl(
                    isAvailable ? .git : .none,
                    for: worktree.repositoryRootURL.standardizedFileURL.path
                )
                runtimeRegistry?.metadataCoordinator.refresh(
                    worktreeIds: [worktree.id],
                    in: worktree.repositoryRootURL.standardizedFileURL.path
                )
            }
        }
    }
}
