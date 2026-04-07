// WorkspaceAttention.swift
// Devys - Workspace-owned attention and notification models.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Workspace

enum WorkspaceAttentionSource: String, Codable, CaseIterable, Sendable {
    case terminal
    case claude
    case codex
    case run
    case build

    var displayName: String {
        switch self {
        case .terminal:
            return "Shell"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .run:
            return "Run"
        case .build:
            return "Build"
        }
    }
}

enum WorkspaceAttentionKind: String, Codable, Sendable {
    case unread
    case waiting
    case completed
}

struct WorkspaceAttentionNotification: Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceID: Workspace.ID
    let source: WorkspaceAttentionSource
    let kind: WorkspaceAttentionKind
    let terminalID: UUID?
    var title: String
    var subtitle: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        kind: WorkspaceAttentionKind,
        terminalID: UUID? = nil,
        title: String,
        subtitle: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.source = source
        self.kind = kind
        self.terminalID = terminalID
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

struct WorkspaceAttentionSummary: Equatable, Sendable {
    let unreadCount: Int
    let waitingCount: Int
    let latestUnreadAt: Date?
    let latestWaitingSource: WorkspaceAttentionSource?

    var hasAttention: Bool {
        unreadCount > 0
    }
}
