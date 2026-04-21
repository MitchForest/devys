// WorktreeRuntimeRegistry.swift
// Devys - Legacy per-workspace runtime bridge for engine handles during migration.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import ACPClientKit
import AppFeatures
import Workspace

@MainActor
@Observable
final class WorktreeRuntimeRegistry {
    @ObservationIgnored
    private var runtimeFactories: RuntimeFactories?

    struct RuntimeFactories {
        let makeFileTreeModel: @MainActor (URL) -> FileTreeModel?
    }

    private var runtimesByWorkspaceID: [Workspace.ID: WorktreeRuntimeState] = [:]
    private(set) var activeWorkspaceID: Workspace.ID?
    private var filesSidebarVisible = true

    func configure(
        makeFileTreeModel: @escaping @MainActor (URL) -> FileTreeModel?
    ) {
        guard runtimeFactories == nil else { return }
        runtimeFactories = RuntimeFactories(
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

    func fileTreeModel(for workspaceID: Workspace.ID) -> FileTreeModel? {
        runtimesByWorkspaceID[workspaceID]?.fileTreeModel
    }

    func chatSession(id: ChatSessionID, in workspaceID: Workspace.ID) -> ChatSessionRuntime? {
        runtimesByWorkspaceID[workspaceID]?.chatSession(id: id)
    }

    func allChatSessions(for workspaceID: Workspace.ID) -> [ChatSessionRuntime] {
        runtimesByWorkspaceID[workspaceID]?.allChatSessions ?? []
    }

    @discardableResult
    func ensureChatSession(
        in workspaceID: Workspace.ID,
        sessionID: ChatSessionID,
        descriptor: ACPAgentDescriptor
    ) -> ChatSessionRuntime? {
        runtimesByWorkspaceID[workspaceID]?.ensureChatSession(
            workspaceID: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        )
    }

    func rekeyChatSession(
        _ runtime: ChatSessionRuntime,
        in workspaceID: Workspace.ID,
        to sessionID: ChatSessionID,
        descriptor: ACPAgentDescriptor
    ) {
        runtimesByWorkspaceID[workspaceID]?.rekeyChatSession(
            runtime,
            to: sessionID,
            descriptor: descriptor
        )
    }

    func removeChatSession(id: ChatSessionID, in workspaceID: Workspace.ID) {
        runtimesByWorkspaceID[workspaceID]?.removeChatSession(id: id)
    }

    func removeAllChatSessions(in workspaceID: Workspace.ID) {
        runtimesByWorkspaceID[workspaceID]?.removeAllChatSessions()
    }

    func activate(
        worktree: Worktree,
        filesSidebarVisible: Bool
    ) {
        if let activeWorkspaceID,
           let activeRuntime = runtimesByWorkspaceID[activeWorkspaceID],
           activeWorkspaceID != worktree.id {
            activeRuntime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
        }

        let runtime = ensureRuntime(for: worktree)
        activeWorkspaceID = worktree.id
        self.filesSidebarVisible = filesSidebarVisible
        runtime.setFilesSidebarVisible(filesSidebarVisible, makeFileTreeModel: makeFileTreeModel)
    }

    func deactivateActiveWorkspace() {
        if let activeWorkspaceID,
           let runtime = runtimesByWorkspaceID[activeWorkspaceID] {
            runtime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
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

    func discardWorkspace(
        _ workspaceID: Workspace.ID
    ) {
        guard let runtime = runtimesByWorkspaceID.removeValue(forKey: workspaceID) else { return }
        runtime.setFilesSidebarVisible(false, makeFileTreeModel: makeFileTreeModel)
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

    func makeFileTreeModel(rootURL: URL) -> FileTreeModel? {
        guard let runtimeFactories else { return nil }
        return runtimeFactories.makeFileTreeModel(rootURL)
    }
}

@MainActor
private final class WorktreeRuntimeState {
    let worktree: Worktree
    let editorSessionPool = EditorSessionPool()
    private var chatSessionsByID: [ChatSessionID: ChatSessionRuntime] = [:]
    var fileTreeModel: FileTreeModel?

    init(worktree: Worktree) {
        self.worktree = worktree
    }

    var allChatSessions: [ChatSessionRuntime] {
        Array(chatSessionsByID.values)
    }

    func ensureFileTreeModel(using factory: (URL) -> FileTreeModel?) {
        if fileTreeModel == nil {
            fileTreeModel = factory(worktree.workingDirectory)
        }
    }

    func chatSession(id: ChatSessionID) -> ChatSessionRuntime? {
        chatSessionsByID[id]
    }

    @discardableResult
    func ensureChatSession(
        workspaceID: Workspace.ID,
        sessionID: ChatSessionID,
        descriptor: ACPAgentDescriptor
    ) -> ChatSessionRuntime {
        if let existing = chatSessionsByID[sessionID] {
            return existing
        }

        let runtime = ChatSessionRuntime(
            workspaceID: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        )
        chatSessionsByID[sessionID] = runtime
        return runtime
    }

    func rekeyChatSession(
        _ runtime: ChatSessionRuntime,
        to sessionID: ChatSessionID,
        descriptor: ACPAgentDescriptor
    ) {
        chatSessionsByID.removeValue(forKey: runtime.sessionID)
        runtime.updateSessionIdentity(sessionID: sessionID, descriptor: descriptor)
        chatSessionsByID[sessionID] = runtime
    }

    func removeChatSession(id: ChatSessionID) {
        chatSessionsByID.removeValue(forKey: id)
    }

    func removeAllChatSessions() {
        chatSessionsByID.removeAll()
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
}
