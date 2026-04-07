// GitRepositoryInfo.swift
// Model for repository state summary.

import Foundation

/// Summary of repository state.
public struct GitRepositoryInfo: Equatable, Sendable {
    public let currentBranch: String?
    public let upstreamBranch: String?
    public let aheadCount: Int
    public let behindCount: Int
    
    public init(
        currentBranch: String?,
        upstreamBranch: String? = nil,
        aheadCount: Int = 0,
        behindCount: Int = 0
    ) {
        self.currentBranch = currentBranch
        self.upstreamBranch = upstreamBranch
        self.aheadCount = aheadCount
        self.behindCount = behindCount
    }
    
    public var hasUpstream: Bool {
        upstreamBranch?.isEmpty == false
    }

    /// Ahead/behind counts for display (e.g., "↑2 ↓1").
    public var syncCountsText: String {
        var parts: [String] = []
        if aheadCount > 0 {
            parts.append("↑\(aheadCount)")
        }
        if behindCount > 0 {
            parts.append("↓\(behindCount)")
        }
        return parts.isEmpty ? "" : parts.joined(separator: " ")
    }

    /// Status string used by existing shell surfaces.
    public var syncStatus: String {
        syncCountsText
    }

    public var remoteStatusLabel: String {
        guard hasUpstream else { return "NO UPSTREAM" }
        let counts = syncCountsText
        return counts.isEmpty ? "UP TO DATE" : counts
    }
}
