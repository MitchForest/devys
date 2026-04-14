// ContentView+NotificationRouting.swift
// Notification routing for global shell commands.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

@MainActor
extension ContentView {
    func applyNotificationModifiers<V: View>(_ view: V) -> some View {
        routeWorkspaceAttentionNotifications(
            routeWorkspaceCommandNotifications(
                routeDocumentCommandNotifications(view)
            )
        )
    }

    private func routeDocumentCommandNotifications<V: View>(_ view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .devysAddRepository)) { _ in
                requestOpenRepository()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysOpenCommandPalette)) { _ in
                activeSearchRequest = WorkspaceSearchRequest(mode: .commands)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysOpenFileSearch)) { _ in
                activeSearchRequest = WorkspaceSearchRequest(mode: .files)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysOpenTextSearch)) { _ in
                activeSearchRequest = WorkspaceSearchRequest(mode: .textSearch)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowEditorFind)) { _ in
                showFindInActiveEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSave)) { _ in
                saveActiveEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSaveAs)) { _ in
                saveActiveEditorAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSaveAll)) { _ in
                Task { @MainActor in
                    _ = await EditorSessionRegistry.shared.saveAll()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSaveDefaultLayout)) { _ in
                saveDefaultLayout()
            }
    }

    private func routeWorkspaceCommandNotifications<V: View>(_ view: V) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .devysShowFilesSidebar)) { _ in
                showSidebarItem(.files)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowChangesSidebar)) { _ in
                showSidebarItem(.changes)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowPortsSidebar)) { _ in
                showSidebarItem(.ports)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSelectWorkspaceIndex)) { notification in
                guard let index = notification.userInfo?["index"] as? Int else { return }
                selectWorkspace(at: index)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSelectNextWorkspace)) { _ in
                selectAdjacentWorkspace(offset: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysSelectPreviousWorkspace)) { _ in
                selectAdjacentWorkspace(offset: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysToggleSidebar)) { _ in
                toggleSidebar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysToggleNavigator)) { _ in
                toggleNavigator()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysLaunchShell)) { _ in
                openShellForSelectedWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysLaunchClaude)) { _ in
                launchClaudeForSelectedWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysLaunchCodex)) { _ in
                launchCodexForSelectedWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysRunWorkspaceProfile)) { _ in
                runSelectedWorkspaceProfile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysRevealCurrentWorkspaceInNavigator)) { _ in
                revealCurrentWorkspaceInNavigator()
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysJumpToLatestUnreadWorkspace)) { _ in
                Task { @MainActor in
                    await jumpToLatestUnreadWorkspace()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .devysShowWorkspaceNotifications)) { _ in
                isNotificationsPanelPresented = true
            }
    }

    private func routeWorkspaceAttentionNotifications<V: View>(_ view: V) -> some View {
        view.onReceive(NotificationCenter.default.publisher(for: .devysWorkspaceAttentionIngress)) { notification in
            guard let payload = try? WorkspaceAttentionIngress.decode(userInfo: notification.userInfo) else {
                return
            }
            guard shouldDisplayAttentionPayload(payload) else { return }
            workspaceAttentionStore.ingest(payload)
        }
    }
}
