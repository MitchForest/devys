// WorkspaceFileTreeGitStatusIndex.swift
// Devys - Workspace-local Git status projection for the file tree.

import Foundation
import Git
import Workspace

enum WorkspaceFileTreeGitStatusCode: String, CaseIterable, Sendable {
    case unmerged = "U"
    case deleted = "D"
    case modified = "M"
    case added = "A"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "I"

    init?(gitStatus: GitFileStatus) {
        switch gitStatus {
        case .unmerged:
            self = .unmerged
        case .deleted:
            self = .deleted
        case .modified:
            self = .modified
        case .added:
            self = .added
        case .renamed:
            self = .renamed
        case .copied:
            self = .copied
        case .untracked:
            self = .untracked
        case .ignored:
            self = .ignored
        }
    }

    static let displayPriority: [WorkspaceFileTreeGitStatusCode] = [
        .unmerged,
        .deleted,
        .modified,
        .added,
        .renamed,
        .copied,
        .untracked,
        .ignored
    ]
}

struct WorkspaceFileTreeGitStatusSummary: Equatable, Sendable {
    let codes: [WorkspaceFileTreeGitStatusCode]

    var primaryCode: WorkspaceFileTreeGitStatusCode? {
        codes.first
    }

    var label: String {
        guard !codes.isEmpty else { return "" }
        let visibleCodes = codes.prefix(2).map(\.rawValue).joined(separator: " ")
        return codes.count > 2 ? "\(visibleCodes) +" : visibleCodes
    }
}

struct WorkspaceFileTreeGitStatusIndex: Equatable, Sendable {
    let rootURL: URL

    private let fileSummariesByRelativePath: [String: WorkspaceFileTreeGitStatusSummary]
    private let directorySummariesByRelativePath: [String: WorkspaceFileTreeGitStatusSummary]

    init(rootURL: URL, changes: [GitFileChange]) {
        let normalizedRootURL = rootURL.standardizedFileURL
        self.rootURL = normalizedRootURL

        var fileCodesByRelativePath: [String: Set<WorkspaceFileTreeGitStatusCode>] = [:]
        var directoryCodesByRelativePath: [String: Set<WorkspaceFileTreeGitStatusCode>] = [:]

        for change in changes {
            guard let code = WorkspaceFileTreeGitStatusCode(gitStatus: change.status) else { continue }
            let relativePath = Self.normalizeRelativePath(change.path)
            guard !relativePath.isEmpty else { continue }

            fileCodesByRelativePath[relativePath, default: []].insert(code)

            for ancestor in Self.ancestorPaths(for: relativePath) {
                directoryCodesByRelativePath[ancestor, default: []].insert(code)
            }
        }

        self.fileSummariesByRelativePath = Self.makeSummaries(from: fileCodesByRelativePath)
        self.directorySummariesByRelativePath = Self.makeSummaries(from: directoryCodesByRelativePath)
    }

    @MainActor
    func summary(for node: CEWorkspaceFileNode) -> WorkspaceFileTreeGitStatusSummary? {
        guard let relativePath = relativePath(for: node.url) else { return nil }
        if node.isDirectory {
            return directorySummariesByRelativePath[relativePath]
        }
        return fileSummariesByRelativePath[relativePath]
    }

    private func relativePath(for url: URL) -> String? {
        let normalizedURL = url.standardizedFileURL
        let rootPath = rootURL.path
        let nodePath = normalizedURL.path

        guard nodePath.hasPrefix(rootPath) else { return nil }

        var relativePath = String(nodePath.dropFirst(rootPath.count))
        if relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }

        return relativePath.isEmpty ? nil : Self.normalizeRelativePath(relativePath)
    }

    private static func makeSummaries(
        from codesByRelativePath: [String: Set<WorkspaceFileTreeGitStatusCode>]
    ) -> [String: WorkspaceFileTreeGitStatusSummary] {
        Dictionary(uniqueKeysWithValues: codesByRelativePath.map { path, codes in
            (path, WorkspaceFileTreeGitStatusSummary(codes: sortedCodes(from: codes)))
        })
    }

    private static func sortedCodes(
        from codes: Set<WorkspaceFileTreeGitStatusCode>
    ) -> [WorkspaceFileTreeGitStatusCode] {
        WorkspaceFileTreeGitStatusCode.displayPriority.filter { codes.contains($0) }
    }

    private static func normalizeRelativePath(_ path: String) -> String {
        let standardized = NSString(string: path).standardizingPath
        return standardized.replacingOccurrences(of: "\\", with: "/")
    }

    private static func ancestorPaths(for path: String) -> [String] {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return [] }

        return (1..<(components.count)).map { index in
            components.prefix(index).joined(separator: "/")
        }
    }
}
