// ContentView+WorkspaceState.swift
// Devys - Phase 4 topology/runtime bridge during migration.

import AppFeatures
import Foundation
import Workspace

@MainActor
extension ContentView {
    func persistVisibleWorkspaceState() {
        guard let visibleWorkspaceID else { return }
        workspaceViewStatesByID[visibleWorkspaceID] = WorkspaceViewState(
            editorSessions: editorSessions,
            closeBypass: closeBypass,
            closeInFlight: closeInFlight
        )
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    func restoreWorkspaceState(for worktree: Worktree) {
        let workspaceID = worktree.id
        if store.selectedWorkspaceID != workspaceID {
            store.send(.selectWorkspace(workspaceID))
        }
        let hadSavedState = workspaceViewStatesByID[workspaceID] != nil
            || store.workspaceShells[workspaceID]?.layout != nil
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

        runtimeRegistry.activate(
            worktree: worktree,
            filesSidebarVisible: reducerFilesSidebarVisible
        )

        let state = persistedWorkspaceViewState(for: workspaceID)

        editorSessions = state.editorSessions
        closeBypass = state.closeBypass
        closeInFlight = state.closeInFlight
        restoreWorkspaceController(for: workspaceID, hadSavedState: hadSavedState)

        bindRepositoryCapability(for: worktree)

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

    private func restoreWorkspaceController(
        for workspaceID: Workspace.ID,
        hadSavedState: Bool
    ) {
        controller = ContentView.makeSplitController()
        configureSplitDelegate()

        if !hadSavedState {
            ensureWorkspaceLayout(for: workspaceID)
            applyDefaultLayout(workspaceID: workspaceID)
            return
        }

        if store.workspaceShells[workspaceID]?.layout != nil {
            renderWorkspaceLayout(for: workspaceID)
            return
        }

        ensureWorkspaceLayout(for: workspaceID)
        applyDefaultLayout(workspaceID: workspaceID)
    }

    func discardWorkspaceState(_ workspaceID: Workspace.ID) {
        let wasVisibleWorkspace = visibleWorkspaceID == workspaceID
        workspaceOperationalController.clearWorkspace(workspaceID)
        let agentSessions = runtimeRegistry.allAgentSessions(for: workspaceID)
        let editorSessionPool = runtimeRegistry.editorSessionPool(for: workspaceID)
        runtimeRegistry.discardWorkspace(workspaceID)
        disposeWorkspaceState(
            workspaceID,
            editorSessionPool: editorSessionPool,
            agentSessions: agentSessions
        )
        hostedContentBridge.discardWorkspace(workspaceID)
        workspaceViewStatesByID.removeValue(forKey: workspaceID)
        store.send(.removeHostedWorkspaceContent(workspaceID))
        if wasVisibleWorkspace {
            resetWorkspaceState()
        }
    }

    private func disposeWorkspaceState(
        _ workspaceID: Workspace.ID,
        editorSessionPool: EditorSessionPool?,
        agentSessions: [AgentSessionRuntime]
    ) {
        let state = persistedWorkspaceViewState(for: workspaceID)

        for terminalID in workspaceTerminalRegistry.sessions(for: workspaceID).keys {
            shutdownWorkspaceTerminalSession(
                id: terminalID,
                in: workspaceID,
                terminateHostedSession: true
            )
        }
        workspaceBackgroundProcessRegistry.shutdownAll(in: workspaceID)
        store.send(.setWorkspaceRunState(workspaceID: workspaceID, nil))
        for session in agentSessions {
            Task {
                await session.teardown()
            }
        }
        runtimeRegistry.removeAllAgentSessions(in: workspaceID)

        for tabID in state.editorSessions.keys {
            if let session = state.editorSessions[tabID] {
                editorSessionPool?.release(url: session.url)
            }
            editorSessionRegistry.unregister(tabId: tabID)
        }
    }

    private func bindRepositoryCapability(for worktree: Worktree) {
        guard let gitStore = runtimeRegistry.gitStore(for: worktree.id) else { return }
        let windowStore = store
        gitStore.onRepositoryAvailabilityDidUpdate = { isAvailable in
            Task { @MainActor in
                windowStore.send(
                    .setRepositorySourceControl(
                        isAvailable ? .git : .none,
                        for: worktree.repositoryRootURL.standardizedFileURL.path
                    )
                )
                windowStore.send(
                    .requestWorkspaceOperationalMetadataRefresh(
                        worktreeIDs: [worktree.id],
                        repositoryID: worktree.repositoryRootURL.standardizedFileURL.path
                    )
                )
            }
        }
    }
}
