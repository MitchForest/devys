// ContentView+Notifications.swift
// Devys - Workspace notification navigation and panel models.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import SwiftUI
import Workspace

struct WorkspaceNotificationPanelItem: Identifiable {
    let notification: WorkspaceAttentionNotification
    let repositoryID: Repository.ID
    let repositoryName: String
    let workspaceName: String

    var id: UUID {
        notification.id
    }
}

@MainActor
extension ContentView {
    var notificationsPanelContent: some View {
        ContentViewNotificationsPanelSurface(
            workspaceCatalog: workspaceCatalog,
            workspaceAttentionStore: workspaceAttentionStore,
            onOpen: { item in
                Task { @MainActor in
                    await openNotification(item.notification)
                }
            },
            onClear: { item in
                clearNotification(item.notification)
            }
        )
    }

    func shouldDisplayAttentionPayload(_ payload: WorkspaceAttentionIngressPayload) -> Bool {
        switch payload.source {
        case .terminal:
            return appSettings.notifications.terminalActivity
        case .claude, .codex, .run, .build:
            return appSettings.notifications.agentActivity
        }
    }

    func jumpToLatestUnreadWorkspace() async {
        guard let notification = workspaceAttentionStore.latestUnreadNotification() else { return }
        await openNotification(notification)
    }

    func openNotification(_ notification: WorkspaceAttentionNotification) async {
        guard let context = workspaceContext(for: notification.workspaceID) else {
            workspaceAttentionStore.clearNotification(notification.id)
            return
        }

        isNotificationsPanelPresented = false
        await selectWorkspace(notification.workspaceID, in: context.repository.id)

        if let terminalID = notification.terminalID {
            let content = TabContent.terminal(workspaceID: notification.workspaceID, id: terminalID)
            if let existingTabID = findExistingTab(for: content) {
                selectTab(existingTabID)
            } else if workspaceTerminalRegistry.session(id: terminalID, in: notification.workspaceID) != nil {
                openInPermanentTab(content: content)
            }
            markTerminalNotificationRead(terminalID)
            return
        }

        workspaceAttentionStore.clearNotification(notification.id)
    }

    func clearNotification(_ notification: WorkspaceAttentionNotification) {
        if let terminalID = notification.terminalID {
            markTerminalNotificationRead(terminalID)
            return
        }
        workspaceAttentionStore.clearNotification(notification.id)
    }

    private func workspaceContext(
        for workspaceID: Workspace.ID
    ) -> (repository: Repository, worktree: Worktree)? {
        workspaceCatalog.workspaceContext(for: workspaceID)
    }
}
