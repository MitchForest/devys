// WorktreeRuntimeRegistry.swift
// Devys - Stable per-workspace runtime ownership.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import Workspace
import Git

@MainActor
struct WorktreeRuntimeHandle {
    let workspaceID: Workspace.ID
    let worktree: Worktree
    let shellState: WorkspaceShellState
    let fileTreeModel: FileTreeModel?
    let gitStatusIndex: WorkspaceFileTreeGitStatusIndex?

    var gitStore: GitStore? {
        shellState.gitStore
    }

    var agentRuntimeRegistry: WorkspaceAgentRuntimeRegistry {
        shellState.agentRuntimeRegistry
    }
}

@MainActor
@Observable
final class WorktreeRuntimeRegistry {
    @ObservationIgnored
    private var container: AppContainer?

    private var runtimesByWorkspaceID: [Workspace.ID: WorktreeRuntimeState] = [:]
    private(set) var activeWorkspaceID: Workspace.ID?
    private var filesSidebarVisible = true

    let metadataCoordinator = WorktreeMetadataCoordinator()
    let portCoordinator = WorkspacePortOwnershipCoordinator()

    func configure(container: AppContainer) {
        guard self.container == nil else { return }
        self.container = container
    }
}

@MainActor
extension WorktreeRuntimeRegistry {
    var activeRuntime: WorktreeRuntimeHandle? {
        guard let activeWorkspaceID else { return nil }
        return runtimeHandle(for: activeWorkspaceID)
    }

    var activeShellState: WorkspaceShellState? {
        activeRuntime?.shellState
    }

    var activeGitStore: GitStore? {
        activeRuntime?.gitStore
    }

    var activeGitStatusIndex: WorkspaceFileTreeGitStatusIndex? {
        activeRuntime?.gitStatusIndex
    }

    var storedShellStates: [Workspace.ID: WorkspaceShellState] {
        runtimesByWorkspaceID.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value.shellState
        }
    }

    func containsRuntime(for workspaceID: Workspace.ID) -> Bool {
        runtimesByWorkspaceID[workspaceID] != nil
    }

    func runtimeHandle(for workspaceID: Workspace.ID) -> WorktreeRuntimeHandle? {
        guard let runtime = runtimesByWorkspaceID[workspaceID] else { return nil }
        return WorktreeRuntimeHandle(
            workspaceID: workspaceID,
            worktree: runtime.worktree,
            shellState: runtime.shellState,
            fileTreeModel: runtime.fileTreeModel,
            gitStatusIndex: runtime.gitStatusIndex
        )
    }

    func activate(
        worktree: Worktree,
        filesSidebarVisible: Bool
    ) {
        if let activeWorkspaceID,
           let activeRuntime = runtimesByWorkspaceID[activeWorkspaceID],
           activeWorkspaceID != worktree.id {
            activeRuntime.shellState.gitStore?.stopWatching()
        }

        let runtime = ensureRuntime(for: worktree)
        activeWorkspaceID = worktree.id
        self.filesSidebarVisible = filesSidebarVisible
        runtime.ensureGitStore(using: makeGitStore)
        runtime.shellState.gitStore?.startWatching()
        runtime.setFilesSidebarVisible(filesSidebarVisible, makeFileTreeModel: makeFileTreeModel)
    }

    func deactivateActiveWorkspace() {
        if let activeWorkspaceID,
           let runtime = runtimesByWorkspaceID[activeWorkspaceID] {
            runtime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
            runtime.shellState.gitStore?.stopWatching()
        }
        activeWorkspaceID = nil
    }

    func setFilesSidebarVisible(_ isVisible: Bool) {
        filesSidebarVisible = isVisible
        guard let activeWorkspaceID,
              let runtime = runtimesByWorkspaceID[activeWorkspaceID] else {
            return
        }
        runtime.setFilesSidebarVisible(isVisible, makeFileTreeModel: makeFileTreeModel)
    }

    func shellState(for worktree: Worktree) -> WorkspaceShellState {
        let runtime = ensureRuntime(for: worktree)
        runtime.ensureGitStore(using: makeGitStore)
        return runtime.shellState
    }

    func persistShellState(_ state: WorkspaceShellState) {
        guard let runtime = runtimesByWorkspaceID[state.workspaceID] else { return }
        runtime.shellState = state
    }

    func hydrateGitRuntimeIfNeeded(for workspaceID: Workspace.ID) async {
        guard activeWorkspaceID == workspaceID,
              let runtime = runtimesByWorkspaceID[workspaceID] else {
            return
        }
        await runtime.hydrateGitStoreIfNeeded()
    }

    func discardWorkspace(
        _ workspaceID: Workspace.ID,
        cleanupShellState: ((WorkspaceShellState) -> Void)? = nil
    ) {
        guard let runtime = runtimesByWorkspaceID.removeValue(forKey: workspaceID) else { return }
        runtime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
        runtime.shellState.gitStore?.stopWatching()
        runtime.shellState.gitStore?.cleanup()
        cleanupShellState?(runtime.shellState)
        if activeWorkspaceID == workspaceID {
            activeWorkspaceID = nil
        }
    }
}

@MainActor
private extension WorktreeRuntimeRegistry {
    func ensureRuntime(for worktree: Worktree) -> WorktreeRuntimeState {
        if let existing = runtimesByWorkspaceID[worktree.id] {
            return existing
        }

        let runtime = WorktreeRuntimeState(
            worktree: worktree,
            shellState: WorkspaceShellState(
                workspaceID: worktree.id,
                controller: ContentView.makeSplitController()
            )
        )
        runtimesByWorkspaceID[worktree.id] = runtime
        return runtime
    }

    func makeGitStore(for workingDirectory: URL?) -> GitStore? {
        guard let container, let workingDirectory else { return nil }
        return container.makeGitStore(projectFolder: workingDirectory)
    }

    func makeFileTreeModel(rootURL: URL) -> FileTreeModel? {
        guard let container else { return nil }
        return container.makeFileTreeModel(rootURL: rootURL)
    }
}

@MainActor
private final class WorktreeRuntimeState {
    let worktree: Worktree
    var shellState: WorkspaceShellState
    var fileTreeModel: FileTreeModel?
    var gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    private var hasHydratedGitStore = false
    private var isHydratingGitStore = false

    init(
        worktree: Worktree,
        shellState: WorkspaceShellState
    ) {
        self.worktree = worktree
        self.shellState = shellState
    }

    func ensureGitStore(using factory: (URL?) -> GitStore?) {
        if shellState.gitStore == nil {
            shellState.gitStore = factory(worktree.workingDirectory)
            configureGitStatusIndexBinding()
        }
    }

    func ensureFileTreeModel(using factory: (URL) -> FileTreeModel?) {
        if fileTreeModel == nil {
            fileTreeModel = factory(worktree.workingDirectory)
        }
    }

    func setFilesSidebarVisible(
        _ isVisible: Bool,
        makeFileTreeModel: (URL) -> FileTreeModel?
    ) {
        if isVisible {
            ensureFileTreeModel(using: makeFileTreeModel)
            fileTreeModel?.activate()
        } else {
            fileTreeModel?.deactivate()
        }
    }

    private func configureGitStatusIndexBinding() {
        guard let gitStore = shellState.gitStore else { return }

        gitStatusIndex = WorkspaceFileTreeGitStatusIndex(
            rootURL: worktree.workingDirectory,
            changes: gitStore.allChanges
        )
        gitStore.onChangesDidUpdate = { [weak self] changes in
            guard let self else { return }
            gitStatusIndex = WorkspaceFileTreeGitStatusIndex(
                rootURL: worktree.workingDirectory,
                changes: changes
            )
        }
    }

    func hydrateGitStoreIfNeeded() async {
        guard let gitStore = shellState.gitStore,
              !hasHydratedGitStore,
              !isHydratingGitStore else {
            return
        }

        isHydratingGitStore = true
        defer { isHydratingGitStore = false }

        await gitStore.refresh()
        gitStatusIndex = WorkspaceFileTreeGitStatusIndex(
            rootURL: worktree.workingDirectory,
            changes: gitStore.allChanges
        )
        await gitStore.checkPRAvailability()
        hasHydratedGitStore = true
    }
}
