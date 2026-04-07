// WorkspaceCreationService.swift
// Create and import Devys workspaces from git repositories.

import Foundation
import Workspace

public struct WorkspaceBranchReference: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let isRemote: Bool
    public let isCurrent: Bool

    public init(
        name: String,
        displayName: String,
        isRemote: Bool,
        isCurrent: Bool
    ) {
        self.id = name
        self.name = name
        self.displayName = displayName
        self.isRemote = isRemote
        self.isCurrent = isCurrent
    }
}

public enum WorkspaceCreationRequest: Equatable, Sendable {
    case newBranch(name: String, baseReference: String)
    case existingBranch(WorkspaceBranchReference)
    case pullRequest(PullRequest)
}

public enum WorkspaceCreationError: LocalizedError, Sendable {
    case emptyBranchName
    case worktreePathAlreadyExists(URL)
    case importedWorktreeOutsideRepository(selectedURL: URL, repositoryRoot: URL)
    case detachedHead(URL)
    case invalidPullRequestReference(String)
    case pullRequestBranchUnavailable(number: Int, branchName: String)

    public var errorDescription: String? {
        switch self {
        case .emptyBranchName:
            return "Branch name cannot be empty."
        case .worktreePathAlreadyExists(let url):
            return "A worktree already exists at \(url.path). Remove it or choose a different branch name."
        case .importedWorktreeOutsideRepository(let selectedURL, let repositoryRoot):
            return "\(selectedURL.path) does not belong to repository \(repositoryRoot.path)."
        case .detachedHead(let url):
            return "\(url.path) is not on a branch. Devys workspaces require a branch-backed worktree."
        case .invalidPullRequestReference(let value):
            return "Could not parse a pull request number from '\(value)'."
        case .pullRequestBranchUnavailable(let number, let branchName):
            return "PR #\(number) could not be fetched from origin/\(branchName)."
        }
    }
}

public struct WorkspaceCreationService: Sendable {
    public init() {}

    public func listBranches(in repositoryRoot: URL) async throws -> [WorkspaceBranchReference] {
        let client = GitClient(repositoryURL: repositoryRoot)
        let branches = try await client.branches()

        return branches
            .compactMap { branchReference(from: $0) }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent {
                    return lhs.isCurrent && !rhs.isCurrent
                }
                if lhs.isRemote != rhs.isRemote {
                    return !lhs.isRemote && rhs.isRemote
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    public func listPullRequests(in repositoryRoot: URL) async throws -> [PullRequest] {
        let client = GitHubClient(repositoryURL: repositoryRoot)
        return try await client.listPRs(state: .open)
    }

    public func pullRequest(number: Int, in repositoryRoot: URL) async throws -> PullRequest {
        let client = GitHubClient(repositoryURL: repositoryRoot)
        return try await client.getPR(number: number)
    }

    public func parsePullRequestNumber(from value: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WorkspaceCreationError.invalidPullRequestReference(value)
        }

        if let number = Int(trimmed) {
            return number
        }

        if let match = trimmed.firstMatch(of: /\/pull\/(\d+)/),
           let number = Int(match.1) {
            return number
        }

        throw WorkspaceCreationError.invalidPullRequestReference(value)
    }

    public func suggestedWorktreeLocation(
        forBranchNamed branchName: String,
        in repository: Repository
    ) -> URL {
        let parentDirectory = repository.rootURL.deletingLastPathComponent()
        let pathComponent = "\(repository.displayName)-\(slug(for: branchName))"
        return parentDirectory.appendingPathComponent(pathComponent, isDirectory: true)
    }

    public func createWorkspace(
        in repository: Repository,
        request: WorkspaceCreationRequest
    ) async throws -> Workspace {
        switch request {
        case .newBranch(let name, let baseReference):
            return try await createNewBranchWorkspace(
                in: repository,
                branchName: name,
                baseReference: baseReference
            )
        case .existingBranch(let branch):
            return try await createExistingBranchWorkspace(
                in: repository,
                branch: branch
            )
        case .pullRequest(let pullRequest):
            return try await createPullRequestWorkspace(
                in: repository,
                pullRequest: pullRequest
            )
        }
    }

    public func importWorkspaces(
        at worktreeURLs: [URL],
        into repository: Repository
    ) async throws -> [Workspace] {
        var imported: [Workspace] = []
        for worktreeURL in worktreeURLs {
            let workspace = try await importWorkspace(at: worktreeURL, into: repository)
            imported.append(workspace)
        }
        return imported
    }

    public func importWorkspace(
        at worktreeURL: URL,
        into repository: Repository
    ) async throws -> Workspace {
        let normalizedURL = worktreeURL.standardizedFileURL
        let client = GitClient(repositoryURL: normalizedURL)
        let repositoryClient = GitClient(repositoryURL: repository.rootURL)
        let selectedCommonDirectory = try await client.commonGitDirectory()
        let repositoryCommonDirectory = try await repositoryClient.commonGitDirectory()

        guard selectedCommonDirectory == repositoryCommonDirectory else {
            throw WorkspaceCreationError.importedWorktreeOutsideRepository(
                selectedURL: normalizedURL,
                repositoryRoot: repository.rootURL
            )
        }

        let branchName = try normalizedBranchName(try await client.getCurrentBranch(), worktreeURL: normalizedURL)

        return Workspace(
            repositoryID: repository.id,
            branchName: branchName,
            worktreeURL: normalizedURL,
            kind: .imported
        )
    }

    private func branchReference(from branch: GitBranch) -> WorkspaceBranchReference? {
        let normalizedName = branch.isRemote
            ? normalizedRemoteReference(branch.name)
            : branch.name
        let displayName = branch.isRemote
            ? normalizedRemoteBranchName(branch.name)
            : branch.name

        guard normalizedName != "origin/HEAD" else {
            return nil
        }

        return WorkspaceBranchReference(
            name: normalizedName,
            displayName: displayName,
            isRemote: branch.isRemote,
            isCurrent: branch.isCurrent
        )
    }

    private func availableWorktreeLocation(
        forBranchNamed branchName: String,
        in repository: Repository
    ) throws -> URL {
        let location = suggestedWorktreeLocation(forBranchNamed: branchName, in: repository)
        if FileManager.default.fileExists(atPath: location.path) {
            throw WorkspaceCreationError.worktreePathAlreadyExists(location)
        }
        return location
    }

    private func createNewBranchWorkspace(
        in repository: Repository,
        branchName: String,
        baseReference: String
    ) async throws -> Workspace {
        let normalizedBranchName = try normalizedBranchName(branchName)
        let location = try availableWorktreeLocation(
            forBranchNamed: normalizedBranchName,
            in: repository
        )

        _ = try await DefaultGitWorktreeService().createWorktree(
            at: location,
            branchName: normalizedBranchName,
            baseRef: normalizedReference(baseReference),
            in: repository.rootURL
        )

        return Workspace(
            repositoryID: repository.id,
            branchName: normalizedBranchName,
            worktreeURL: location,
            kind: .branch
        )
    }

    private func createExistingBranchWorkspace(
        in repository: Repository,
        branch: WorkspaceBranchReference
    ) async throws -> Workspace {
        let location = try availableWorktreeLocation(
            forBranchNamed: branch.displayName,
            in: repository
        )

        if branch.isRemote {
            let localBranchName = normalizedRemoteBranchName(branch.name)
            _ = try await DefaultGitWorktreeService().createWorktree(
                at: location,
                branchName: localBranchName,
                baseRef: normalizedRemoteReference(branch.name),
                in: repository.rootURL
            )

            return Workspace(
                repositoryID: repository.id,
                branchName: localBranchName,
                worktreeURL: location,
                kind: .branch
            )
        }

        let normalizedBranchName = try normalizedBranchName(branch.name)
        _ = try await DefaultGitWorktreeService().createWorktree(
            at: location,
            branchName: normalizedBranchName,
            baseRef: nil,
            in: repository.rootURL
        )

        return Workspace(
            repositoryID: repository.id,
            branchName: normalizedBranchName,
            worktreeURL: location,
            kind: .branch
        )
    }

    private func createPullRequestWorkspace(
        in repository: Repository,
        pullRequest: PullRequest
    ) async throws -> Workspace {
        let localBranchName = "pr/\(pullRequest.number)-\(slug(for: pullRequest.headBranch))"
        let location = try availableWorktreeLocation(
            forBranchNamed: localBranchName,
            in: repository
        )
        let client = GitClient(repositoryURL: repository.rootURL)
        let remoteBranch = "refs/heads/\(pullRequest.headBranch):refs/remotes/origin/\(pullRequest.headBranch)"

        do {
            try await client.fetch(remote: "origin", refspec: remoteBranch)
        } catch {
            throw WorkspaceCreationError.pullRequestBranchUnavailable(
                number: pullRequest.number,
                branchName: pullRequest.headBranch
            )
        }

        _ = try await DefaultGitWorktreeService().createWorktree(
            at: location,
            branchName: localBranchName,
            baseRef: "origin/\(pullRequest.headBranch)",
            in: repository.rootURL
        )

        return Workspace(
            repositoryID: repository.id,
            branchName: localBranchName,
            worktreeURL: location,
            kind: .pullRequest
        )
    }

    private func normalizedBranchName(
        _ value: String,
        worktreeURL: URL? = nil
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if let worktreeURL {
                throw WorkspaceCreationError.detachedHead(worktreeURL)
            }
            throw WorkspaceCreationError.emptyBranchName
        }
        return trimmed
    }

    private func normalizedReference(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedRemoteReference(_ value: String) -> String {
        if value.hasPrefix("remotes/") {
            return String(value.dropFirst("remotes/".count))
        }
        return value
    }

    private func normalizedRemoteBranchName(_ value: String) -> String {
        let normalizedReference = normalizedRemoteReference(value)
        let parts = normalizedReference.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else {
            return normalizedReference
        }
        return String(parts[1])
    }

    private func slug(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapped = trimmed.map { character -> Character in
            if character.isLetter || character.isNumber || character == "." || character == "_" {
                return character
            }
            return "-"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if collapsed.isEmpty {
            return "workspace"
        }

        return collapsed
    }
}
