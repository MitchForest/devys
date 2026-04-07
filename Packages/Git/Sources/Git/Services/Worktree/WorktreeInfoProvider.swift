// WorktreeInfoProvider.swift
// Worktree info provider abstraction.

import Foundation

public protocol WorktreeInfoProvider: Sendable {
    func branchName(for worktreeURL: URL) async -> String?
    func lineChanges(for worktreeURL: URL) async -> WorktreeLineChanges?
    func repositoryInfo(for worktreeURL: URL) async -> GitRepositoryInfo?
    func isPullRequestAvailable(for repositoryRoot: URL) async -> Bool
    func pullRequests(for repositoryRoot: URL, branches: [String]) async -> [String: PullRequest]
}

public struct DefaultWorktreeInfoProvider: WorktreeInfoProvider {
    public init() {}

    public func branchName(for worktreeURL: URL) async -> String? {
        let client = GitClient(repositoryURL: worktreeURL)
        return try? await client.getCurrentBranch()
    }

    public func lineChanges(for worktreeURL: URL) async -> WorktreeLineChanges? {
        let client = GitClient(repositoryURL: worktreeURL)
        return try? await client.lineChanges()
    }

    public func repositoryInfo(for worktreeURL: URL) async -> GitRepositoryInfo? {
        let client = GitClient(repositoryURL: worktreeURL)
        return try? await client.repositoryInfo()
    }

    public func isPullRequestAvailable(for repositoryRoot: URL) async -> Bool {
        let client = GitHubClient(repositoryURL: repositoryRoot)
        return await client.isAvailable()
    }

    public func pullRequests(for repositoryRoot: URL, branches: [String]) async -> [String: PullRequest] {
        let client = GitHubClient(repositoryURL: repositoryRoot)
        let isAvailable = await client.isAvailable()
        guard isAvailable else { return [:] }

        let branchSet = Set(branches)
        guard !branchSet.isEmpty else { return [:] }

        let prs = (try? await client.listPRs(state: .open, author: nil, limit: 50)) ?? []
        var mapping: [String: PullRequest] = [:]
        for pr in prs where branchSet.contains(pr.headBranch) {
            mapping[pr.headBranch] = pr
        }
        return mapping
    }
}
