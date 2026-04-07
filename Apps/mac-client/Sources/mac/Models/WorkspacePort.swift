// WorkspacePort.swift
// Devys - Workspace-owned listening port models.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Workspace

enum WorkspacePortOwnership: String, Equatable, Sendable {
    case owned
    case conflicted
}

struct WorkspacePort: Identifiable, Equatable, Sendable {
    let workspaceID: Workspace.ID
    let port: Int
    let processIDs: [Int32]
    let processNames: [String]
    let ownership: WorkspacePortOwnership

    var id: String {
        "\(workspaceID):\(port)"
    }
}

struct WorkspacePortSummary: Equatable, Sendable {
    let totalCount: Int
    let conflictCount: Int

    var hasPorts: Bool {
        totalCount > 0
    }

    var hasConflicts: Bool {
        conflictCount > 0
    }
}
