// ContentView+Notifications.swift
// Devys - Workspace notification navigation and panel models.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import SwiftUI
import Workspace

struct WorkspaceNotificationPanelItem: Identifiable {
    let notification: WorkspaceAttentionNotification
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
            items: workspaceNotificationPanelItems,
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

    var workspaceNotificationPanelItems: [WorkspaceNotificationPanelItem] {
        workspaceOperationalState.pendingNotifications.compactMap { notification in
            guard let context = windowWorkspaceContext(for: notification.workspaceID) else {
                return nil
            }

            return WorkspaceNotificationPanelItem(
                notification: notification,
                repositoryName: context.repository.displayName,
                workspaceName: context.worktree.name
            )
        }
    }

    func jumpToLatestUnreadWorkspace() async {
        guard let notification = workspaceOperationalState.latestUnreadNotification() else { return }
        await openNotification(notification)
    }

    func openNotification(_ notification: WorkspaceAttentionNotification) async {
        guard let context = windowWorkspaceContext(for: notification.workspaceID) else {
            store.send(.clearAttentionNotification(notification.id))
            return
        }

        store.send(.setNotificationsPanelPresented(false))
        await selectWorkspace(notification.workspaceID, in: context.repository.id)

        if let terminalID = notification.terminalID {
            let content = WorkspaceTabContent.terminal(workspaceID: notification.workspaceID, id: terminalID)
            if let existingTabID = findExistingTab(for: content) {
                selectTab(existingTabID)
            } else if workspaceTerminalRegistry.session(id: terminalID, in: notification.workspaceID) != nil {
                openInPermanentTab(content: content)
            }
            markTerminalNotificationRead(terminalID)
            return
        }

        store.send(.clearAttentionNotification(notification.id))
    }

    func clearNotification(_ notification: WorkspaceAttentionNotification) {
        if let terminalID = notification.terminalID {
            markTerminalNotificationRead(terminalID)
            return
        }
        store.send(.clearAttentionNotification(notification.id))
    }
}
