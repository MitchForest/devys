// GitHubClient.swift
// Actor for GitHub operations via `gh` CLI.

import Foundation

/// Actor for GitHub operations via `gh` CLI.
actor GitHubClient {
    private let repositoryURL: URL
    
    init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }
    
    // MARK: - Availability
    
    /// Check if `gh` CLI is available and authenticated.
    func isAvailable() async -> Bool {
        do {
            _ = try await runGH("auth", "status")
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Pull Requests
    
    /// List pull requests.
    func listPRs(
        state: PRStateFilter = .open,
        author: String? = nil,
        limit: Int = 30
    ) async throws -> [PullRequest] {
        var args = [
            "pr", "list",
            "--json", prJSONFields,
            "--limit", "\(limit)",
            "--state", state.rawValue
        ]
        
        if let author = author {
            args += ["--author", author]
        }
        
        let output = try await runGH(args)
        return try parsePRList(output)
    }
    
    /// Get files changed in a PR.
    func getPRFiles(number: Int) async throws -> [PRFile] {
        let output = try await runGH(
            "pr",
            "view",
            "\(number)",
            "--json",
            "files"
        )
        return try parsePRFiles(output)
    }

    /// Get a single pull request.
    func getPR(number: Int) async throws -> PullRequest {
        let output = try await runGH(
            "pr",
            "view",
            "\(number)",
            "--json",
            prJSONFields
        )
        guard let pullRequest = try parsePRList(output).first else {
            throw PRError.notFound(number)
        }
        return pullRequest
    }
    
    /// Create a new PR.
    func createPR(
        title: String,
        body: String,
        base: String? = nil,
        draft: Bool = false
    ) async throws -> Int {
        var args = [
            "pr", "create",
            "--title", title,
            "--body", body
        ]
        
        if let base = base {
            args += ["--base", base]
        }
        
        if draft {
            args.append("--draft")
        }
        
        let output = try await runGH(args)
        // Output is the PR URL, extract number from it
        if let match = output.firstMatch(of: /\/pull\/(\d+)/) {
            return Int(match.1) ?? 0
        }
        return 0
    }
    
    /// Checkout a PR locally.
    func checkoutPR(number: Int) async throws {
        _ = try await runGH("pr", "checkout", "\(number)")
    }
    
    // MARK: - Merge
    
    /// Merge a PR.
    func merge(number: Int, method: MergeMethod = .squash, deleteHead: Bool = true) async throws {
        var args = ["pr", "merge", "\(number)"]
        
        switch method {
        case .merge:
            args.append("--merge")
        case .squash:
            args.append("--squash")
        case .rebase:
            args.append("--rebase")
        }
        
        if deleteHead {
            args.append("--delete-branch")
        }
        
        _ = try await runGH(args)
    }
    
    // MARK: - Helpers
    
    /// Get the web URL for a PR.
    func prURL(number: Int) async throws -> URL? {
        let output = try await runGH(
            "pr",
            "view",
            "\(number)",
            "--json",
            "url"
        )
        guard let data = output.data(using: .utf8) else { return nil }
        let container = try JSONDecoder().decode(PRURLContainer.self, from: data)
        return URL(string: container.url)
    }
    
    // MARK: - Private
    
    private let prJSONFields = [
        "id",
        "number",
        "title",
        "body",
        "state",
        "author",
        "headRefName",
        "baseRefName",
        "createdAt",
        "updatedAt",
        "isDraft",
        "statusCheckRollup",
        "reviewDecision",
        "additions",
        "deletions",
        "changedFiles"
    ].joined(separator: ",")
    
    private func runGH(_ arguments: String...) async throws -> String {
        try await runGH(Array(arguments))
    }
    
    private func runGH(_ arguments: [String]) async throws -> String {
        try Task.checkCancellation()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.currentDirectoryURL = repositoryURL
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
        } catch {
            throw PRError.ghNotInstalled
        }
        
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            let lowercased = stderr.lowercased()
            if lowercased.contains("rate limit") || lowercased.contains("api rate limit") {
                throw PRError.rateLimited
            }
            if lowercased.contains("not logged") || lowercased.contains("authentication") {
                throw PRError.notAuthenticated
            }
            throw PRError.commandFailed(arguments: arguments, stderr: stderr, status: process.terminationStatus)
        }
        
        return stdout
    }
    
    private func parsePRList(_ json: String) throws -> [PullRequest] {
        guard let data = json.data(using: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // gh returns an array for list, single object for view
        if json.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let raw = try decoder.decode([RawPR].self, from: data)
            return raw.map { $0.toPullRequest() }
        } else {
            let raw = try decoder.decode(RawPR.self, from: data)
            return [raw.toPullRequest()]
        }
    }
    
    private func parsePRFiles(_ json: String) throws -> [PRFile] {
        guard let data = json.data(using: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        let container = try decoder.decode(FilesContainer.self, from: data)
        return container.files.map { $0.toPRFile() }
    }
}

// MARK: - JSON Decoding Types

private struct RawPR: Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let author: AuthorInfo
    let headRefName: String
    let baseRefName: String
    let createdAt: Date
    let updatedAt: Date
    let isDraft: Bool
    let statusCheckRollup: [StatusCheck]?
    let reviewDecision: String?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    
    struct AuthorInfo: Codable {
        let login: String
    }
    
    struct StatusCheck: Codable {
        let state: String?
        let conclusion: String?
    }
    
    func toPullRequest() -> PullRequest {
        let checksStatus: ChecksStatus? = {
            guard let checks = statusCheckRollup, !checks.isEmpty else { return nil }
            let conclusions = checks.compactMap { $0.conclusion ?? $0.state }
            if conclusions.contains("FAILURE") || conclusions.contains("ERROR") {
                return .failing
            } else if conclusions.contains("PENDING") || conclusions.contains("IN_PROGRESS") {
                return .pending
            } else if conclusions.allSatisfy({ $0 == "SUCCESS" || $0 == "NEUTRAL" || $0 == "SKIPPED" }) {
                return .passing
            }
            return .pending
        }()
        
        let review: ReviewDecision? = reviewDecision.flatMap { ReviewDecision(rawValue: $0) }
        
        return PullRequest(
            id: id,
            number: number,
            title: title,
            body: body,
            state: PRState(rawValue: state) ?? .open,
            author: author.login,
            headBranch: headRefName,
            baseBranch: baseRefName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDraft: isDraft,
            checksStatus: checksStatus,
            reviewDecision: review,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            changedFiles: changedFiles ?? 0
        )
    }
}

private struct FilesContainer: Codable {
    let files: [RawFile]
}

private struct RawFile: Codable {
    let path: String
    let additions: Int
    let deletions: Int
    let status: String?
    let patch: String?
    
    func toPRFile() -> PRFile {
        let fileStatus: PRFileStatus = {
            switch status?.lowercased() {
            case "added": return .added
            case "removed", "deleted": return .deleted
            case "renamed": return .renamed
            case "copied": return .copied
            default: return .modified
            }
        }()
        
        return PRFile(
            path: path,
            status: fileStatus,
            additions: additions,
            deletions: deletions,
            patch: patch
        )
    }
}

private struct PRURLContainer: Codable {
    let url: String
}
