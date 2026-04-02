// GitBranch.swift
// Model for a git branch.

import Foundation

/// A git branch (local or remote).
struct GitBranch: Identifiable, Equatable, Hashable, Sendable {
    var id: String { name }
    
    let name: String
    let isRemote: Bool
    let isCurrent: Bool
    
    init(
        name: String,
        isRemote: Bool = false,
        isCurrent: Bool = false
    ) {
        self.name = name
        self.isRemote = isRemote
        self.isCurrent = isCurrent
    }
    
    /// Short display name (removes "origin/" prefix for remotes).
    var displayName: String {
        if isRemote, name.hasPrefix("origin/") {
            return String(name.dropFirst("origin/".count))
        }
        return name
    }
}
