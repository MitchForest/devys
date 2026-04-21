// WorktreeInfoProvider.swift
// Worktree info provider abstraction.

import Foundation

public struct WorktreeGitSnapshot: Equatable, Sendable {
    public let isRepositoryAvailable: Bool
    public let branchName: String?
    public let repositoryInfo: GitRepositoryInfo?
    public let lineChanges: WorktreeLineChanges?
    public let statusSummary: WorktreeStatusSummary?
    public let changes: [GitFileChange]
    public let errorMessage: String?

    public init(
        isRepositoryAvailable: Bool,
        branchName: String? = nil,
        repositoryInfo: GitRepositoryInfo? = nil,
        lineChanges: WorktreeLineChanges? = nil,
        statusSummary: WorktreeStatusSummary? = nil,
        changes: [GitFileChange] = [],
        errorMessage: String? = nil
    ) {
        self.isRepositoryAvailable = isRepositoryAvailable
        self.branchName = branchName
        self.repositoryInfo = repositoryInfo
        self.lineChanges = lineChanges
        self.statusSummary = statusSummary
        self.changes = changes
        self.errorMessage = errorMessage
    }
}

public protocol WorktreeInfoProvider: Sendable {
    func snapshot(for worktreeURL: URL) async -> WorktreeGitSnapshot
    func isPullRequestAvailable(for repositoryRoot: URL) async -> Bool
    func pullRequests(for repositoryRoot: URL, branches: [String]) async -> [String: PullRequest]
}

public struct DefaultWorktreeInfoProvider: WorktreeInfoProvider {
    public init() {}

    public func snapshot(for worktreeURL: URL) async -> WorktreeGitSnapshot {
        let client = GitClient(repositoryURL: worktreeURL)
        do {
            _ = try await client.repositoryRoot()
            // Deliberately `status()`, not `statusIncludingIgnored()`: the ignored
            // expansion runs `git ls-files --others -i --exclude-standard`, which
            // materializes every path under .gitignore (node_modules, DerivedData,
            // caches). In a real repo that's 10^5+ entries and the sidebar's
            // ForEach collapses the main thread trying to render them.
            let changes = try await client.status()
            let repositoryInfo = try await client.repositoryInfo()
            let lineChanges = try await client.lineChanges()
            return WorktreeGitSnapshot(
                isRepositoryAvailable: true,
                branchName: repositoryInfo.currentBranch,
                repositoryInfo: repositoryInfo,
                lineChanges: lineChanges,
                statusSummary: WorktreeStatusSummary(changes: changes),
                changes: changes
            )
        } catch {
            if let gitError = error as? GitError,
               case .notRepository = gitError {
                return WorktreeGitSnapshot(isRepositoryAvailable: false)
            }
            return WorktreeGitSnapshot(
                isRepositoryAvailable: true,
                errorMessage: error.localizedDescription
            )
        }
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
