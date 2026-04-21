// GitService.swift
// DevysGit
//
// Git + GitHub operations abstraction.

import Foundation

@MainActor
protocol GitService {
    var hasPRClient: Bool { get }
    func isRepositoryAvailable() async -> Bool
    func initializeRepository() async throws

    func status() async throws -> [GitFileChange]
    // periphery:ignore - explicit opt-in status path kept for ignored-aware explorer workflows
    func statusIncludingIgnored() async throws -> [GitFileChange]
    func repositoryInfo() async throws -> GitRepositoryInfo
    // periphery:ignore - used by alternate diff presentation paths not seen by Periphery
    func diff(
        for path: String,
        staged: Bool,
        contextLines: Int,
        ignoreWhitespace: Bool
    ) async throws -> String
    func diffSnapshot(
        for path: String,
        staged: Bool,
        contextLines: Int,
        ignoreWhitespace: Bool
    ) async throws -> DiffSnapshot

    func stage(_ path: String) async throws
    func unstage(_ path: String) async throws
    func stageAll() async throws
    func unstageAll() async throws
    func stageHunk(_ hunk: DiffHunk, for path: String) async throws
    func unstageHunk(_ hunk: DiffHunk, for path: String) async throws
    func stagePatch(_ patch: String) async throws
    func unstagePatch(_ patch: String) async throws
    func discard(_ path: String) async throws
    func discardUntracked(_ path: String) async throws
    func discardHunk(_ hunk: DiffHunk, for path: String) async throws
    func discardPatch(_ patch: String) async throws

    func commit(message: String) async throws -> String
    func fetch() async throws
    func push() async throws
    func pull() async throws

    func branches() async throws -> [GitBranch]
    func checkout(branch: String) async throws
    func createBranch(name: String) async throws
    func deleteBranch(name: String, force: Bool) async throws

    func log(count: Int) async throws -> [GitCommit]
    func show(commit: String) async throws -> String

    func isPRAvailable() async -> Bool
    func listPRs(state: PRStateFilter) async throws -> [PullRequest]
    func getPRFiles(number: Int) async throws -> [PRFile]
    func checkoutPR(number: Int) async throws
    func createPR(title: String, body: String, base: String, draft: Bool) async throws -> Int
    func mergePR(number: Int, method: MergeMethod) async throws
    func prURL(number: Int) async -> URL?
}

@MainActor
struct DefaultGitService: GitService {
    private let gitClient: GitClient?
    private let githubClient: GitHubClient?
    private let repositoryURL: URL?

    var hasPRClient: Bool { githubClient != nil }

    init(repositoryURL: URL?) {
        self.repositoryURL = repositoryURL
        if let repositoryURL {
            self.gitClient = GitClient(repositoryURL: repositoryURL)
            self.githubClient = GitHubClient(repositoryURL: repositoryURL)
        } else {
            self.gitClient = nil
            self.githubClient = nil
        }
    }

    func isRepositoryAvailable() async -> Bool {
        guard let gitClient else { return false }
        do {
            _ = try await gitClient.repositoryRoot()
            return true
        } catch {
            return false
        }
    }

    func initializeRepository() async throws {
        try await requireGitClient().initializeRepository()
    }

    func status() async throws -> [GitFileChange] {
        try await requireGitClient().status()
    }

    // periphery:ignore - explicit opt-in status path kept for ignored-aware explorer workflows
    func statusIncludingIgnored() async throws -> [GitFileChange] {
        try await requireGitClient().statusIncludingIgnored()
    }

    func repositoryInfo() async throws -> GitRepositoryInfo {
        try await requireGitClient().repositoryInfo()
    }

    // periphery:ignore - used by alternate diff presentation paths not seen by Periphery
    func diff(
        for path: String,
        staged: Bool,
        contextLines: Int,
        ignoreWhitespace: Bool
    ) async throws -> String {
        try await requireGitClient().diff(
            for: path,
            staged: staged,
            contextLines: contextLines,
            ignoreWhitespace: ignoreWhitespace
        )
    }

    func diffSnapshot(
        for path: String,
        staged: Bool,
        contextLines: Int,
        ignoreWhitespace: Bool
    ) async throws -> DiffSnapshot {
        try await requireGitClient().diffSnapshot(
            for: path,
            staged: staged,
            contextLines: contextLines,
            ignoreWhitespace: ignoreWhitespace
        )
    }

    func stage(_ path: String) async throws {
        try await requireGitClient().stage(path)
    }

    func unstage(_ path: String) async throws {
        try await requireGitClient().unstage(path)
    }

    func stageAll() async throws {
        try await requireGitClient().stageAll()
    }

    func unstageAll() async throws {
        try await requireGitClient().unstageAll()
    }

    func stageHunk(_ hunk: DiffHunk, for path: String) async throws {
        try await requireGitClient().stageHunk(hunk, for: path)
    }

    func unstageHunk(_ hunk: DiffHunk, for path: String) async throws {
        try await requireGitClient().unstageHunk(hunk, for: path)
    }

    func stagePatch(_ patch: String) async throws {
        try await requireGitClient().stagePatch(patch)
    }

    func unstagePatch(_ patch: String) async throws {
        try await requireGitClient().unstagePatch(patch)
    }

    func discard(_ path: String) async throws {
        try await requireGitClient().discard(path)
    }

    func discardUntracked(_ path: String) async throws {
        try await requireGitClient().discardUntracked(path)
    }

    func discardHunk(_ hunk: DiffHunk, for path: String) async throws {
        try await requireGitClient().discardHunk(hunk, for: path)
    }

    func discardPatch(_ patch: String) async throws {
        try await requireGitClient().discardPatch(patch)
    }

    func commit(message: String) async throws -> String {
        try await requireGitClient().commit(message: message)
    }

    func fetch() async throws {
        try await requireGitClient().fetch()
    }

    func push() async throws {
        try await requireGitClient().push()
    }

    func pull() async throws {
        try await requireGitClient().pull()
    }

    func branches() async throws -> [GitBranch] {
        try await requireGitClient().branches()
    }

    func checkout(branch: String) async throws {
        try await requireGitClient().checkout(branch: branch)
    }

    func createBranch(name: String) async throws {
        try await requireGitClient().createBranch(name: name)
    }

    func deleteBranch(name: String, force: Bool) async throws {
        try await requireGitClient().deleteBranch(name: name, force: force)
    }

    func log(count: Int) async throws -> [GitCommit] {
        try await requireGitClient().log(count: count)
    }

    func show(commit: String) async throws -> String {
        try await requireGitClient().show(commit: commit)
    }

    func isPRAvailable() async -> Bool {
        guard await isRepositoryAvailable() else { return false }
        guard let githubClient else { return false }
        return await githubClient.isAvailable()
    }

    func listPRs(state: PRStateFilter) async throws -> [PullRequest] {
        try await requireGitHubClient().listPRs(state: state)
    }

    func getPRFiles(number: Int) async throws -> [PRFile] {
        try await requireGitHubClient().getPRFiles(number: number)
    }

    func checkoutPR(number: Int) async throws {
        try await requireGitHubClient().checkoutPR(number: number)
    }

    func createPR(title: String, body: String, base: String, draft: Bool) async throws -> Int {
        try await requireGitHubClient().createPR(title: title, body: body, base: base, draft: draft)
    }

    func mergePR(number: Int, method: MergeMethod) async throws {
        try await requireGitHubClient().merge(number: number, method: method)
    }

    func prURL(number: Int) async -> URL? {
        try? await requireGitHubClient().prURL(number: number)
    }

    private func requireGitClient() throws -> GitClient {
        if let gitClient { return gitClient }
        throw GitError.notRepository(repositoryURL ?? URL(fileURLWithPath: "/"))
    }

    private func requireGitHubClient() throws -> GitHubClient {
        if let githubClient { return githubClient }
        throw PRError.ghNotInstalled
    }
}
