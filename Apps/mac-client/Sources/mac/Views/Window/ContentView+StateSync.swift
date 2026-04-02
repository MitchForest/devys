// ContentView+StateSync.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split
import Git
import Workspace

@MainActor
extension ContentView {
    var sessionMetadataSnapshot: String {
        var parts: [String] = []
        for (id, session) in terminalSessions {
            parts.append("\(id):\(session.tabTitle):\(session.tabIcon)")
        }
        for (id, session) in editorSessions {
            parts.append("\(id):\(session.isDirty)")
        }
        return parts.sorted().joined(separator: "|")
    }

    func cleanupSession(for content: TabContent, tabId: TabID?) {
        switch content {
        case .terminal(let id):
            terminalSessions[id]?.shutdown()
            terminalSessions.removeValue(forKey: id)
            runCommandStore.clearTerminal(id)
        case .editor:
            if let tabId {
                editorSessions.removeValue(forKey: tabId)
                EditorSessionRegistry.shared.unregister(tabId: tabId)
            }
        default:
            break
        }
    }

    func syncTabMetadataFromSessions() {
        for (tabId, content) in tabContents {
            let (title, icon) = tabMetadata(for: content, tabId: tabId)
            let activityIndicator = tabActivityIndicator()
            controller.updateTab(tabId, title: title, icon: icon, activityIndicator: activityIndicator)
        }
    }

    func updateGitStore(for folder: URL?) {
        gitStore?.cleanup()
        gitStore = container.makeGitStore(projectFolder: folder)
        if folder != nil {
            Task {
                await gitStore?.refresh()
                await gitStore?.checkPRAvailability()
            }
        }
    }

    func updateWorktreeManager(for folder: URL?) {
        if worktreeManager == nil {
            worktreeManager = container.makeWorktreeManager()
        }
        if worktreeInfoStore == nil {
            worktreeInfoStore = container.makeWorktreeInfoStore()
        }
        Task {
            await worktreeManager?.refresh(for: folder)
        }
    }

    func syncWorktreeInfoStore() {
        guard let manager = worktreeManager else { return }
        if worktreeInfoStore == nil {
            worktreeInfoStore = container.makeWorktreeInfoStore()
        }
        worktreeInfoStore?.update(
            worktrees: manager.worktrees,
            repositoryRootURL: manager.repositoryRoot
        )
        worktreeInfoStore?.setSelectedWorktreeId(manager.selection.selectedWorktreeId)
        worktreeInfoStore?.refreshAll()
    }

    func syncWorktreeInfoSelection(_ worktreeId: Worktree.ID?) {
        worktreeInfoStore?.setSelectedWorktreeId(worktreeId)
    }

    func syncTerminalNotifications() {
        if terminalNotificationStore == nil {
            terminalNotificationStore = TerminalNotificationStore()
        }
        terminalNotificationStore?.sync(with: terminalSessions)
    }

    func markTerminalNotificationRead(_ terminalId: UUID) {
        terminalNotificationStore?.markRead(
            terminalId: terminalId,
            currentBellCount: terminalSessions[terminalId]?.bellCount
        )
    }
}
