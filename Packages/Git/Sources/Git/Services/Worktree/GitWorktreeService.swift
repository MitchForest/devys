// GitWorktreeService.swift
// Worktree operations via git CLI.

import Foundation
import Workspace

public protocol GitWorktreeService: Sendable {
    func repositoryRoot(for url: URL) async throws -> URL
    func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree]
    func createWorktree(
        at path: URL,
        branchName: String,
        baseRef: String?,
        in repositoryRoot: URL
    ) async throws -> Worktree
    func removeWorktree(_ worktree: Worktree, force: Bool) async throws
    func pruneWorktrees(in repositoryRoot: URL) async throws
}

public struct DefaultGitWorktreeService: GitWorktreeService {
    public init() {}

    public func repositoryRoot(for url: URL) async throws -> URL {
        let client = GitClient(repositoryURL: url)
        return try await client.repositoryRoot()
    }

    public func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree] {
        let client = GitClient(repositoryURL: repositoryRoot)
        let entries = try await client.worktreeList()
        return entries.map { entry in
            Worktree(
                name: entry.branchName ?? entry.path.lastPathComponent,
                detail: relativePath(from: repositoryRoot, to: entry.path),
                workingDirectory: entry.path,
                repositoryRootURL: repositoryRoot,
                createdAt: entry.createdAt
            )
        }
    }

    public func createWorktree(
        at path: URL,
        branchName: String,
        baseRef: String?,
        in repositoryRoot: URL
    ) async throws -> Worktree {
        let client = GitClient(repositoryURL: repositoryRoot)
        try await client.createWorktree(at: path, branchName: branchName, baseRef: baseRef)
        let detail = relativePath(from: repositoryRoot, to: path)
        return Worktree(
            name: branchName,
            detail: detail,
            workingDirectory: path,
            repositoryRootURL: repositoryRoot,
            createdAt: nil
        )
    }

    public func removeWorktree(_ worktree: Worktree, force: Bool) async throws {
        let client = GitClient(repositoryURL: worktree.repositoryRootURL)
        try await client.removeWorktree(at: worktree.workingDirectory, force: force)
    }

    public func pruneWorktrees(in repositoryRoot: URL) async throws {
        let client = GitClient(repositoryURL: repositoryRoot)
        try await client.pruneWorktrees()
    }

    private func relativePath(from base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var index = 0
        while index < baseComponents.count,
              index < targetComponents.count,
              baseComponents[index] == targetComponents[index] {
            index += 1
        }
        let upCount = baseComponents.count - index
        let upComponents = Array(repeating: "..", count: max(0, upCount))
        let remaining = targetComponents[index...]
        let components = upComponents + remaining
        if components.isEmpty {
            return "."
        }
        return components.joined(separator: "/")
    }
}

extension DefaultGitWorktreeService: WorktreeListingService {}
