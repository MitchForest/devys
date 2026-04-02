// GitRepositoryInfo.swift
// Model for repository state summary.

import Foundation

/// Summary of repository state.
struct GitRepositoryInfo: Equatable, Sendable {
    let currentBranch: String?
    let aheadCount: Int
    let behindCount: Int
    
    init(
        currentBranch: String?,
        aheadCount: Int = 0,
        behindCount: Int = 0
    ) {
        self.currentBranch = currentBranch
        self.aheadCount = aheadCount
        self.behindCount = behindCount
    }
    
    /// Status string for display (e.g., "↑2 ↓1").
    var syncStatus: String {
        var parts: [String] = []
        if aheadCount > 0 {
            parts.append("↑\(aheadCount)")
        }
        if behindCount > 0 {
            parts.append("↓\(behindCount)")
        }
        return parts.isEmpty ? "" : parts.joined(separator: " ")
    }
}
