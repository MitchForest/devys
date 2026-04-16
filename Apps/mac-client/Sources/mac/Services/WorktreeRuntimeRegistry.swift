// WorktreeRuntimeRegistry.swift
// Devys - Legacy per-workspace runtime bridge for engine handles during migration.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import ACPClientKit
import AppFeatures
import Workspace
import Git

@MainActor
@Observable
final class WorktreeRuntimeRegistry {
    @ObservationIgnored
    private var runtimeFactories: RuntimeFactories?

    struct RuntimeFactories {
        let makeGitStore: @MainActor (URL?) -> GitStore?
        let makeFileTreeModel: @MainActor (URL) -> FileTreeModel?
    }

    private var runtimesByWorkspaceID: [Workspace.ID: WorktreeRuntimeState] = [:]
    private(set) var activeWorkspaceID: Workspace.ID?
    private var filesSidebarVisible = true

    func configure(
        makeGitStore: @escaping @MainActor (URL?) -> GitStore?,
        makeFileTreeModel: @escaping @MainActor (URL) -> FileTreeModel?
    ) {
        guard runtimeFactories == nil else { return }
        runtimeFactories = RuntimeFactories(
            makeGitStore: makeGitStore,
            makeFileTreeModel: makeFileTreeModel
        )
    }
}

@MainActor
extension WorktreeRuntimeRegistry {
    var activeWorktree: Worktree? {
        guard let activeWorkspaceID else { return nil }
        return worktree(for: activeWorkspaceID)
    }

    var activeGitStore: GitStore? {
        guard let activeWorkspaceID else { return nil }
        return gitStore(for: activeWorkspaceID)
    }

    var activeGitStatusIndex: WorkspaceFileTreeGitStatusIndex? {
        guard let activeWorkspaceID else { return nil }
        return gitStatusIndex(for: activeWorkspaceID)
    }

    var activeFileTreeModel: FileTreeModel? {
        guard let activeWorkspaceID else { return nil }
        return fileTreeModel(for: activeWorkspaceID)
    }

    func containsRuntime(for workspaceID: Workspace.ID) -> Bool {
        runtimesByWorkspaceID[workspaceID] != nil
    }

    func worktree(for workspaceID: Workspace.ID) -> Worktree? {
        runtimesByWorkspaceID[workspaceID]?.worktree
    }

    func editorSessionPool(for workspaceID: Workspace.ID) -> EditorSessionPool? {
        runtimesByWorkspaceID[workspaceID]?.editorSessionPool
    }

    func gitStore(for workspaceID: Workspace.ID) -> GitStore? {
        runtimesByWorkspaceID[workspaceID]?.gitStore
    }

    func fileTreeModel(for workspaceID: Workspace.ID) -> FileTreeModel? {
        runtimesByWorkspaceID[workspaceID]?.fileTreeModel
    }

    func gitStatusIndex(for workspaceID: Workspace.ID) -> WorkspaceFileTreeGitStatusIndex? {
        runtimesByWorkspaceID[workspaceID]?.gitStatusIndex
    }

    func agentSession(id: AgentSessionID, in workspaceID: Workspace.ID) -> AgentSessionRuntime? {
        runtimesByWorkspaceID[workspaceID]?.agentSession(id: id)
    }

    func allAgentSessions(for workspaceID: Workspace.ID) -> [AgentSessionRuntime] {
        runtimesByWorkspaceID[workspaceID]?.allAgentSessions ?? []
    }

    @discardableResult
    func ensureAgentSession(
        in workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) -> AgentSessionRuntime? {
        runtimesByWorkspaceID[workspaceID]?.ensureAgentSession(
            workspaceID: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        )
    }

    func rekeyAgentSession(
        _ runtime: AgentSessionRuntime,
        in workspaceID: Workspace.ID,
        to sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) {
        runtimesByWorkspaceID[workspaceID]?.rekeyAgentSession(
            runtime,
            to: sessionID,
            descriptor: descriptor
        )
    }

    func removeAgentSession(id: AgentSessionID, in workspaceID: Workspace.ID) {
        runtimesByWorkspaceID[workspaceID]?.removeAgentSession(id: id)
    }

    func removeAllAgentSessions(in workspaceID: Workspace.ID) {
        runtimesByWorkspaceID[workspaceID]?.removeAllAgentSessions()
    }

    func activate(
        worktree: Worktree,
        filesSidebarVisible: Bool
    ) {
        if let activeWorkspaceID,
           let activeRuntime = runtimesByWorkspaceID[activeWorkspaceID],
           activeWorkspaceID != worktree.id {
            activeRuntime.gitStore?.stopWatching()
        }

        let runtime = ensureRuntime(for: worktree)
        activeWorkspaceID = worktree.id
        self.filesSidebarVisible = filesSidebarVisible
        runtime.ensureGitStore(using: makeGitStore)
        runtime.gitStore?.startWatching()
        runtime.setFilesSidebarVisible(filesSidebarVisible, makeFileTreeModel: makeFileTreeModel)
    }

    func deactivateActiveWorkspace() {
        if let activeWorkspaceID,
           let runtime = runtimesByWorkspaceID[activeWorkspaceID] {
            runtime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
            runtime.gitStore?.stopWatching()
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

    func hydrateGitRuntimeIfNeeded(for workspaceID: Workspace.ID) async {
        guard activeWorkspaceID == workspaceID,
              let runtime = runtimesByWorkspaceID[workspaceID] else {
            return
        }
        await runtime.hydrateGitStoreIfNeeded()
    }

    func discardWorkspace(
        _ workspaceID: Workspace.ID
    ) {
        guard let runtime = runtimesByWorkspaceID.removeValue(forKey: workspaceID) else { return }
        runtime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
        runtime.gitStore?.stopWatching()
        runtime.gitStore?.cleanup()
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

        let runtime = WorktreeRuntimeState(worktree: worktree)
        runtimesByWorkspaceID[worktree.id] = runtime
        return runtime
    }

    func makeGitStore(for workingDirectory: URL?) -> GitStore? {
        guard let runtimeFactories, let workingDirectory else { return nil }
        return runtimeFactories.makeGitStore(workingDirectory)
    }

    func makeFileTreeModel(rootURL: URL) -> FileTreeModel? {
        guard let runtimeFactories else { return nil }
        return runtimeFactories.makeFileTreeModel(rootURL)
    }
}

@MainActor
private final class WorktreeRuntimeState {
    let worktree: Worktree
    let editorSessionPool = EditorSessionPool()
    var gitStore: GitStore?
    private var agentSessionsByID: [AgentSessionID: AgentSessionRuntime] = [:]
    var fileTreeModel: FileTreeModel?
    var gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    private var hasHydratedGitStore = false
    private var isHydratingGitStore = false

    init(worktree: Worktree) {
        self.worktree = worktree
    }

    var allAgentSessions: [AgentSessionRuntime] {
        Array(agentSessionsByID.values)
    }

    func ensureGitStore(using factory: (URL?) -> GitStore?) {
        if gitStore == nil {
            gitStore = factory(worktree.workingDirectory)
            configureGitStatusIndexBinding()
        }
    }

    func ensureFileTreeModel(using factory: (URL) -> FileTreeModel?) {
        if fileTreeModel == nil {
            fileTreeModel = factory(worktree.workingDirectory)
        }
    }

    func agentSession(id: AgentSessionID) -> AgentSessionRuntime? {
        agentSessionsByID[id]
    }

    @discardableResult
    func ensureAgentSession(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) -> AgentSessionRuntime {
        if let existing = agentSessionsByID[sessionID] {
            return existing
        }

        let runtime = AgentSessionRuntime(
            workspaceID: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        )
        agentSessionsByID[sessionID] = runtime
        return runtime
    }

    func rekeyAgentSession(
        _ runtime: AgentSessionRuntime,
        to sessionID: AgentSessionID,
        descriptor: ACPAgentDescriptor
    ) {
        agentSessionsByID.removeValue(forKey: runtime.sessionID)
        runtime.updateSessionIdentity(sessionID: sessionID, descriptor: descriptor)
        agentSessionsByID[sessionID] = runtime
    }

    func removeAgentSession(id: AgentSessionID) {
        agentSessionsByID.removeValue(forKey: id)
    }

    func removeAllAgentSessions() {
        agentSessionsByID.removeAll()
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
        guard let gitStore else { return }

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
        guard let gitStore,
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
