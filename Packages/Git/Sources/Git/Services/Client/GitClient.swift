// GitClient.swift
// Actor for performing git operations via CLI.

import Foundation

/// Actor for performing git operations via CLI.
/// All operations are async and cancellable.
actor GitClient {
    private let repositoryURL: URL
    private let commandTimeout: TimeInterval
    private let pollIntervalNanoseconds: UInt64 = 100_000_000
    
    init(repositoryURL: URL, timeout: TimeInterval = 10) {
        self.repositoryURL = repositoryURL
        self.commandTimeout = timeout
    }
    
}

extension GitClient {
    // MARK: - Status
    
    /// Get current working tree status.
    func status() async throws -> [GitFileChange] {
        let output = try await runGit("status", "--porcelain=v1")
        return parseStatusOutput(output)
    }
    
    private func parseStatusOutput(_ output: String) -> [GitFileChange] {
        var changes: [GitFileChange] = []
        
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.count >= 3 else { continue }
            
            let lineStr = String(line)
            let indexStatus = lineStr.prefix(1)
            let worktreeStatus = String(lineStr.dropFirst(1).prefix(1))
            let path = String(lineStr.dropFirst(3))
            
            // Handle renames (R followed by old -> new paths)
            var actualPath = path
            if path.contains(" -> ") {
                let parts = path.components(separatedBy: " -> ")
                actualPath = parts.last ?? path
            }
            
            // Staged changes
            if let status = parseStatusChar(String(indexStatus)),
               indexStatus != " " && indexStatus != "?" {
                changes.append(GitFileChange(
                    path: actualPath,
                    status: status,
                    isStaged: true
                ))
            }
            
            // Unstaged changes
            if let status = parseStatusChar(worktreeStatus), worktreeStatus != " " {
                if indexStatus == "?" && worktreeStatus == "?" {
                    changes.append(GitFileChange(
                        path: actualPath,
                        status: .untracked,
                        isStaged: false
                    ))
                } else {
                    changes.append(GitFileChange(
                        path: actualPath,
                        status: status,
                        isStaged: false
                    ))
                }
            }
        }
        
        return changes
    }
    
    private func parseStatusChar(_ char: String) -> GitFileStatus? {
        switch char {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "?": return .untracked
        case "!": return .ignored
        case "U": return .unmerged
        default: return nil
        }
    }
    
    // MARK: - Repository Info
    
    /// Get repository info (branch, ahead/behind).
    func repositoryInfo() async throws -> GitRepositoryInfo {
        let branch = try? await getCurrentBranch()
        let (ahead, behind) = (try? await getAheadBehind()) ?? (0, 0)
        
        return GitRepositoryInfo(
            currentBranch: branch,
            aheadCount: ahead,
            behindCount: behind
        )
    }
    
    /// Get the current branch name.
    func getCurrentBranch() async throws -> String {
        let output = try await runGit("branch", "--show-current")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Get ahead/behind count relative to upstream.
    func getAheadBehind() async throws -> (ahead: Int, behind: Int) {
        let output = try await runGit("rev-list", "--left-right", "--count", "@{u}...HEAD")
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }

    // MARK: - Worktrees

    /// Resolve the repository root for the current working directory.
    func repositoryRoot() async throws -> URL {
        let output = try await runGit("rev-parse", "--show-toplevel")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitError.invalidOutput("Empty repository root")
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    /// List worktrees using `git worktree list --porcelain`.
    func worktreeList() async throws -> [GitWorktreeEntry] {
        let output = try await runGit("worktree", "list", "--porcelain")
        return GitWorktreeListParser.parse(output)
    }

    /// Create a worktree at the given path.
    func createWorktree(at path: URL, branchName: String, baseRef: String?) async throws {
        var args = ["worktree", "add"]
        if let baseRef, !baseRef.isEmpty {
            args += ["-b", branchName]
        }
        args.append(path.path)
        if let baseRef, !baseRef.isEmpty {
            args.append(baseRef)
        } else if !branchName.isEmpty {
            args.append(branchName)
        }
        _ = try await runGitCommand(arguments: args, timeout: commandTimeout)
    }

    /// Remove a worktree by path.
    func removeWorktree(at path: URL, force: Bool) async throws {
        var args = ["worktree", "remove"]
        if force {
            args.append("--force")
        }
        args.append(path.path)
        _ = try await runGitCommand(arguments: args, timeout: commandTimeout)
    }

    /// Prune stale worktrees.
    func pruneWorktrees() async throws {
        _ = try await runGit("worktree", "prune")
    }
    
    // MARK: - Diff
    
    /// Get diff for a file (staged or unstaged).
    func diff(
        for path: String,
        staged: Bool,
        contextLines: Int = 3,
        ignoreWhitespace: Bool = false
    ) async throws -> String {
        var args = ["diff", "--no-color", "--unified=\(contextLines)"]
        if ignoreWhitespace {
            args.append("-w")
        }
        if staged {
            args.append("--cached")
        }
        args += ["--", path]
        return try await runGitCommand(arguments: args, timeout: commandTimeout)
    }
    
    /// Get shortstat line changes for the working directory.
    func lineChanges() async throws -> WorktreeLineChanges {
        let output = try await runGit("diff", "HEAD", "--shortstat")
        return parseShortstat(output)
    }
    
    // MARK: - Staging
    
    /// Stage a file.
    func stage(_ path: String) async throws {
        _ = try await runGit("add", path)
    }
    
    /// Unstage a file.
    func unstage(_ path: String) async throws {
        _ = try await runGit("reset", "HEAD", "--", path)
    }
    
    /// Stage all changes.
    func stageAll() async throws {
        _ = try await runGit("add", "-A")
    }
    
    /// Unstage all changes.
    func unstageAll() async throws {
        _ = try await runGit("reset", "HEAD")
    }
    
    /// Stage a single hunk.
    func stageHunk(_ hunk: DiffHunk, for path: String) async throws {
        let patch = hunk.toPatch(oldPath: path, newPath: path)
        try await applyPatch(patch, cached: true, reverse: false)
    }
    
    /// Unstage a single hunk.
    func unstageHunk(_ hunk: DiffHunk, for path: String) async throws {
        let patch = hunk.toPatch(oldPath: path, newPath: path)
        try await applyPatch(patch, cached: true, reverse: true)
    }
    
    /// Discard a single hunk by applying its reverse patch.
    /// This reverts the hunk's changes to match HEAD.
    func discardHunk(_ hunk: DiffHunk, for path: String) async throws {
        let patch = hunk.toPatch(oldPath: path, newPath: path)
        try await applyPatch(patch, cached: false, reverse: true)
    }
    
    private func applyPatch(_ patch: String, cached: Bool, reverse: Bool) async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".patch")
        
        try patch.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        var args = ["apply"]
        if cached {
            args.append("--cached")
        }
        if reverse {
            args.append("--reverse")
        }
        args.append(tempFile.path)
        
        _ = try await runGitCommand(arguments: args, timeout: commandTimeout)
    }
    
    // MARK: - Discard
    
    /// Discard changes to a tracked file (revert to HEAD).
    func discard(_ path: String) async throws {
        _ = try await runGit("checkout", "--", path)
    }
    
    /// Discard an untracked file (delete it).
    func discardUntracked(_ path: String) async throws {
        _ = try await runGit("clean", "-f", "--", path)
    }
    
    // MARK: - Commit
    
    /// Commit staged changes.
    @discardableResult
    func commit(message: String) async throws -> String {
        let output = try await runGit("commit", "-m", message)
        // Parse commit hash from output like "[main abc1234] message"
        if let match = output.firstMatch(of: /\[[\w\-\/]+ ([a-f0-9]+)\]/) {
            return String(match.1)
        }
        return output
    }
    
    // MARK: - Remote Operations
    
    /// Push to remote.
    func push(remote: String = "origin", branch: String? = nil, setUpstream: Bool = false) async throws {
        var args = ["push"]
        if setUpstream {
            args.append("-u")
        }
        args.append(remote)
        if let branch = branch {
            args.append(branch)
        }
        _ = try await runGitCommand(arguments: args, timeout: 60)
    }
    
    /// Pull from remote.
    func pull(remote: String = "origin", branch: String? = nil) async throws {
        var args = ["pull", remote]
        if let branch = branch {
            args.append(branch)
        }
        _ = try await runGitCommand(arguments: args, timeout: 60)
    }
    
    // MARK: - Branch Operations
    
    /// List branches.
    func branches(includeRemote: Bool = true) async throws -> [GitBranch] {
        var args = ["branch", "--format=%(refname:short)|%(HEAD)"]
        if includeRemote {
            args.append("-a")
        }
        
        let output = try await runGitCommand(arguments: args, timeout: commandTimeout)
        return output.split(separator: "\n").compactMap { line in
            let parts = String(line).split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            
            let name = String(parts[0])
            let isCurrent = parts[1] == "*"
            let hasRemotePrefix = name.hasPrefix("remotes/")
            let hasSlash = name.contains("/")
            let isFeature = name.hasPrefix("feature/")
            let isBugfix = name.hasPrefix("bugfix/")
            let isRemote = hasRemotePrefix || (hasSlash && !isFeature && !isBugfix)
            
            return GitBranch(
                name: name,
                isRemote: isRemote,
                isCurrent: isCurrent
            )
        }
    }
    
    /// Checkout a branch.
    func checkout(branch: String) async throws {
        _ = try await runGit("checkout", branch)
    }
    
    /// Create a new branch.
    func createBranch(name: String, from: String? = nil, checkout: Bool = true) async throws {
        if checkout {
            if let from = from {
                _ = try await runGit("checkout", "-b", name, from)
            } else {
                _ = try await runGit("checkout", "-b", name)
            }
        } else {
            if let from = from {
                _ = try await runGit("branch", name, from)
            } else {
                _ = try await runGit("branch", name)
            }
        }
    }
    
    /// Delete a branch.
    func deleteBranch(name: String, force: Bool = false) async throws {
        let flag = force ? "-D" : "-d"
        _ = try await runGit("branch", flag, name)
    }
    
    // MARK: - Commit History
    
    /// Get commit history.
    func log(count: Int = 50, branch: String? = nil) async throws -> [GitCommit] {
        var args = [
            "log",
            "--format=%H|%h|%an|%at|%s",
            "-\(count)"
        ]
        if let branch = branch {
            args.append(branch)
        }
        
        let output = try await runGitCommand(arguments: args, timeout: commandTimeout)
        return output.split(separator: "\n").compactMap { line in
            let parts = String(line).split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count >= 5 else { return nil }
            
            let timestamp = TimeInterval(parts[3]) ?? 0
            return GitCommit(
                hash: String(parts[0]),
                shortHash: String(parts[1]),
                authorName: String(parts[2]),
                date: Date(timeIntervalSince1970: timestamp),
                message: String(parts[4])
            )
        }
    }
    
    /// Show a commit diff.
    func show(commit: String) async throws -> String {
        try await runGit("show", "--no-color", "--unified=5", commit)
    }

    private func parseShortstat(_ output: String) -> WorktreeLineChanges {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return WorktreeLineChanges(added: 0, removed: 0)
        }
        var added = 0
        var removed = 0
        if let match = trimmed.firstMatch(of: /(\d+)\s+insertion/) {
            added = Int(match.1) ?? 0
        }
        if let match = trimmed.firstMatch(of: /(\d+)\s+deletion/) {
            removed = Int(match.1) ?? 0
        }
        return WorktreeLineChanges(added: added, removed: removed)
    }
    
    // MARK: - Git Execution
    
    private func runGit(_ arguments: String...) async throws -> String {
        try await runGitCommand(arguments: arguments, timeout: commandTimeout)
    }
    
    private func runGitCommand(arguments: [String], timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        
        async let stdoutData = Self.readToEndAsync(from: stdoutPipe.fileHandleForReading)
        async let stderrData = Self.readToEndAsync(from: stderrPipe.fileHandleForReading)
        
        let status = try await waitForExit(process, arguments: arguments, timeout: timeout)
        let stdout = String(data: await stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: await stderrData, encoding: .utf8) ?? ""
        
        if status != 0 {
            throw makeGitError(arguments: arguments, stdout: stdout, stderr: stderr, status: status)
        }
        
        return stdout
    }
    
    private func waitForExit(_ process: Process, arguments: [String], timeout: TimeInterval) async throws -> Int32 {
        let start = Date()
        
        while process.isRunning {
            if Task.isCancelled {
                Self.terminateProcess(process)
                throw CancellationError()
            }
            
            if timeout > 0, Date().timeIntervalSince(start) >= timeout {
                Self.terminateProcess(process)
                throw GitError.timedOut(arguments: arguments, timeout: timeout)
            }
            
            do {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            } catch {
                Self.terminateProcess(process)
                throw error
            }
        }
        
        return process.terminationStatus
    }
    
    private static func terminateProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
    }
    
    private static func readToEndAsync(from handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
    
    private func makeGitError(arguments: [String], stdout: String, stderr: String, status: Int32) -> GitError {
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedStderr.localizedCaseInsensitiveContains("not a git repository") {
            return .notRepository(repositoryURL)
        }
        
        return .commandFailed(arguments: arguments, stderr: stderr, stdout: stdout, status: status)
    }
}
