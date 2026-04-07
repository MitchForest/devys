// WorkspacePortStore+Support.swift
// Devys - Supporting types and helpers for workspace port detection.

import Foundation
import Workspace

struct ListeningPortRecord: Hashable {
    let processID: Int32
    let processName: String
    let port: Int
}

struct WorkspacePortAssignment {
    let port: Int
    var processIDs: Set<Int32> = []
    var processNames: Set<String> = []
}

struct WorkspacePortOwnershipState {
    let assignmentsByWorkspaceAndPort: [Workspace.ID: [Int: WorkspacePortAssignment]]
    let ambiguousPortsByWorkspace: [Workspace.ID: Set<Int>]
}

struct WorkspacePortRefreshRequest {
    let reason: WorkspacePortStore.RefreshReason
    let workspaceIDs: [Workspace.ID]
}

struct WorkspacePortRefreshRecord: Equatable {
    let reason: WorkspacePortStore.RefreshReason
    let workspaceIDs: [Workspace.ID]
    let workspaceCount: Int
}

extension URL {
    func isDescendant(of parent: URL) -> Bool {
        let standardizedPath = standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return standardizedPath == parentPath || standardizedPath.hasPrefix(parentPath + "/")
    }
}

extension Dictionary where Key == Workspace.ID {
    func filtered(to workspaceIDs: [Workspace.ID]) -> [Workspace.ID: Value] {
        let workspaceIDSet = Set(workspaceIDs)
        return filter { workspaceIDSet.contains($0.key) }
    }
}

func workspacePortNilIfEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
