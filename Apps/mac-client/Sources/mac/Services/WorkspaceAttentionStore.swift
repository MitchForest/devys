// WorkspaceAttentionStore.swift
// Devys - Workspace-scoped attention state.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import Workspace

@MainActor
@Observable
final class WorkspaceAttentionStore {
    private(set) var notificationsByWorkspace: [Workspace.ID: [WorkspaceAttentionNotification]] = [:]

    var summariesByWorkspace: [Workspace.ID: WorkspaceAttentionSummary] {
        notificationsByWorkspace.reduce(into: [:]) { partialResult, pair in
            let summary = summary(for: pair.key)
            if summary.hasAttention {
                partialResult[pair.key] = summary
            }
        }
    }

    var pendingNotifications: [WorkspaceAttentionNotification] {
        notificationsByWorkspace.values
            .flatMap { $0 }
            .sorted(by: notificationSort(lhs:rhs:))
    }

    func notifications(for workspaceID: Workspace.ID?) -> [WorkspaceAttentionNotification] {
        guard let workspaceID else { return [] }
        return (notificationsByWorkspace[workspaceID] ?? [])
            .sorted(by: notificationSort(lhs:rhs:))
    }

    func summary(for workspaceID: Workspace.ID) -> WorkspaceAttentionSummary {
        let notifications = notificationsByWorkspace[workspaceID] ?? []
        let waitingNotifications = notifications.filter { $0.kind == .waiting }
        let latestWaitingNotification = waitingNotifications.max { $0.updatedAt < $1.updatedAt }

        return WorkspaceAttentionSummary(
            unreadCount: notifications.count,
            waitingCount: waitingNotifications.count,
            latestWaitingSource: latestWaitingNotification?.source
        )
    }

    func latestUnreadNotification() -> WorkspaceAttentionNotification? {
        pendingNotifications.first
    }

    func syncFromTerminalRegistry(
        _ registry: WorkspaceTerminalRegistry,
        now: Date = Date()
    ) {
        let workspaceIDs = Set(registry.statesByWorkspace.keys)

        for workspaceID in Array(notificationsByWorkspace.keys) where !workspaceIDs.contains(workspaceID) {
            removeNotifications(in: workspaceID) { $0.source == .terminal }
        }

        for (workspaceID, state) in registry.statesByWorkspace {
            let unreadTerminalIDs = state.unreadTerminalIds

            removeNotifications(in: workspaceID) { notification in
                guard notification.source == .terminal,
                      notification.kind == .unread,
                      let terminalID = notification.terminalID
                else {
                    return false
                }
                return !unreadTerminalIDs.contains(terminalID)
            }

            for terminalID in unreadTerminalIDs {
                upsertNotification(
                    matching: { notification in
                        notification.source == .terminal
                            && notification.kind == .unread
                            && notification.terminalID == terminalID
                    },
                    in: workspaceID,
                    create: {
                        WorkspaceAttentionNotification(
                            workspaceID: workspaceID,
                            source: .terminal,
                            kind: .unread,
                            terminalID: terminalID,
                            title: "Terminal needs attention",
                            subtitle: nil,
                            createdAt: now
                        )
                    },
                    update: { notification in
                        notification.updatedAt = now
                    }
                )
            }
        }
    }

    func recordWaiting(
        in workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        terminalID: UUID? = nil,
        title: String,
        subtitle: String? = nil,
        now: Date = Date()
    ) {
        upsertNotification(
            matching: { notification in
                notification.source == source
                    && notification.kind == .waiting
                    && notification.terminalID == terminalID
            },
            in: workspaceID,
            create: {
                WorkspaceAttentionNotification(
                    workspaceID: workspaceID,
                    source: source,
                    kind: .waiting,
                    terminalID: terminalID,
                    title: title,
                    subtitle: subtitle,
                    createdAt: now
                )
            },
            update: { notification in
                notification.title = title
                notification.subtitle = subtitle
                notification.updatedAt = now
            }
        )
    }

    func recordCompleted(
        in workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        terminalID: UUID? = nil,
        title: String,
        subtitle: String? = nil,
        now: Date = Date()
    ) {
        removeNotifications(in: workspaceID) { notification in
            notification.source == source
                && notification.kind == .waiting
                && notification.terminalID == terminalID
        }

        upsertNotification(
            matching: { notification in
                notification.source == source
                    && notification.kind == .completed
                    && notification.terminalID == terminalID
            },
            in: workspaceID,
            create: {
                WorkspaceAttentionNotification(
                    workspaceID: workspaceID,
                    source: source,
                    kind: .completed,
                    terminalID: terminalID,
                    title: title,
                    subtitle: subtitle,
                    createdAt: now
                )
            },
            update: { notification in
                notification.title = title
                notification.subtitle = subtitle
                notification.updatedAt = now
            }
        )
    }

    func ingest(_ payload: WorkspaceAttentionIngressPayload, now: Date = Date()) {
        switch payload.kind {
        case .waiting:
            recordWaiting(
                in: payload.workspaceID,
                source: payload.source,
                terminalID: payload.terminalID,
                title: payload.title,
                subtitle: payload.subtitle,
                now: now
            )
        case .completed:
            recordCompleted(
                in: payload.workspaceID,
                source: payload.source,
                terminalID: payload.terminalID,
                title: payload.title,
                subtitle: payload.subtitle,
                now: now
            )
        case .unread:
            upsertNotification(
                matching: { notification in
                    notification.source == payload.source
                        && notification.kind == .unread
                        && notification.terminalID == payload.terminalID
                },
                in: payload.workspaceID,
                create: {
                    WorkspaceAttentionNotification(
                        workspaceID: payload.workspaceID,
                        source: payload.source,
                        kind: .unread,
                        terminalID: payload.terminalID,
                        title: payload.title,
                        subtitle: payload.subtitle,
                        createdAt: now
                    )
                },
                update: { notification in
                    notification.title = payload.title
                    notification.subtitle = payload.subtitle
                    notification.updatedAt = now
                }
            )
        }
    }

    func markTerminalRead(_ terminalID: UUID, in workspaceID: Workspace.ID?) {
        guard let workspaceID else { return }
        removeNotifications(in: workspaceID) { $0.terminalID == terminalID }
    }

    func clearNotification(_ notificationID: UUID) {
        for workspaceID in Array(notificationsByWorkspace.keys) {
            removeNotifications(in: workspaceID) { $0.id == notificationID }
        }
    }

    func clearNotifications(from source: WorkspaceAttentionSource) {
        clearNotifications(from: [source])
    }

    func clearNotifications(from sources: Set<WorkspaceAttentionSource>) {
        guard !sources.isEmpty else { return }
        for workspaceID in Array(notificationsByWorkspace.keys) {
            removeNotifications(in: workspaceID) { sources.contains($0.source) }
        }
    }

    func clearWorkspace(_ workspaceID: Workspace.ID) {
        notificationsByWorkspace.removeValue(forKey: workspaceID)
    }

    func removeTerminal(_ terminalID: UUID, in workspaceID: Workspace.ID) {
        removeNotifications(in: workspaceID) { $0.terminalID == terminalID }
    }

    private func upsertNotification(
        matching predicate: (WorkspaceAttentionNotification) -> Bool,
        in workspaceID: Workspace.ID,
        create: () -> WorkspaceAttentionNotification,
        update: (inout WorkspaceAttentionNotification) -> Void
    ) {
        var notifications = notificationsByWorkspace[workspaceID] ?? []
        if let index = notifications.firstIndex(where: predicate) {
            update(&notifications[index])
        } else {
            notifications.append(create())
        }
        notificationsByWorkspace[workspaceID] = notifications
    }

    private func removeNotifications(
        in workspaceID: Workspace.ID,
        _ shouldRemove: (WorkspaceAttentionNotification) -> Bool
    ) {
        guard var notifications = notificationsByWorkspace[workspaceID] else { return }
        notifications.removeAll(where: shouldRemove)
        if notifications.isEmpty {
            notificationsByWorkspace.removeValue(forKey: workspaceID)
        } else {
            notificationsByWorkspace[workspaceID] = notifications
        }
    }

    private func notificationSort(
        lhs: WorkspaceAttentionNotification,
        rhs: WorkspaceAttentionNotification
    ) -> Bool {
        if attentionPriority(for: lhs.kind) != attentionPriority(for: rhs.kind) {
            return attentionPriority(for: lhs.kind) < attentionPriority(for: rhs.kind)
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func attentionPriority(for kind: WorkspaceAttentionKind) -> Int {
        switch kind {
        case .waiting:
            return 0
        case .completed:
            return 1
        case .unread:
            return 2
        }
    }
}
