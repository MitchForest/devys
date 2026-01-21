import Foundation

// MARK: - Git File Status

/// Git status for a single file
public struct GitFileChange: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let path: String
    public let status: GitFileStatus
    public let isStaged: Bool

    public var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public var directory: String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    public init(
        id: UUID = UUID(),
        path: String,
        status: GitFileStatus,
        isStaged: Bool
    ) {
        self.id = id
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
}

// GitFileStatus is defined in FileExplorer/FileItem.swift

// MARK: - Git Repository Info

/// Information about a git repository
public struct GitRepositoryInfo: Sendable, Equatable {
    public let rootURL: URL
    public let currentBranch: String?
    public let remoteURL: URL?
    public let headCommit: String?
    public let isDirty: Bool
    public let aheadCount: Int
    public let behindCount: Int

    public init(
        rootURL: URL,
        currentBranch: String? = nil,
        remoteURL: URL? = nil,
        headCommit: String? = nil,
        isDirty: Bool = false,
        aheadCount: Int = 0,
        behindCount: Int = 0
    ) {
        self.rootURL = rootURL
        self.currentBranch = currentBranch
        self.remoteURL = remoteURL
        self.headCommit = headCommit
        self.isDirty = isDirty
        self.aheadCount = aheadCount
        self.behindCount = behindCount
    }
}

// MARK: - Git Client

/// Actor for performing git operations
public actor GitClient {
    private let repositoryURL: URL

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }

    // MARK: - Status

    /// Get the current git status (staged and unstaged changes)
    public func status() async throws -> [GitFileChange] {
        let output = try await runGit("status", "--porcelain=v1")
        return parseStatusOutput(output)
    }

    /// Parse git status --porcelain output
    private func parseStatusOutput(_ output: String) -> [GitFileChange] {
        var changes: [GitFileChange] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.count >= 3 else { continue }

            let lineStr = String(line)
            let indexStatus = lineStr.prefix(1)
            let worktreeStatus = String(lineStr.dropFirst(1).prefix(1))
            let path = String(lineStr.dropFirst(3))

            // Index (staged) status
            if let status = parseStatusChar(String(indexStatus)), indexStatus != " " && indexStatus != "?" {
                changes.append(GitFileChange(path: path, status: status, isStaged: true))
            }

            // Worktree (unstaged) status
            if let status = parseStatusChar(worktreeStatus), worktreeStatus != " " {
                // Untracked files show as ?? in porcelain format
                if indexStatus == "?" && worktreeStatus == "?" {
                    changes.append(GitFileChange(path: path, status: .untracked, isStaged: false))
                } else {
                    changes.append(GitFileChange(path: path, status: status, isStaged: false))
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

    /// Get repository information
    public func repositoryInfo() async throws -> GitRepositoryInfo {
        let branch = try? await getCurrentBranch()
        let remote = try? await getRemoteURL()
        let head = try? await getHeadCommit()
        let (ahead, behind) = (try? await getAheadBehind()) ?? (0, 0)
        let status = try? await status()
        let isDirty = !(status ?? []).isEmpty

        return GitRepositoryInfo(
            rootURL: repositoryURL,
            currentBranch: branch,
            remoteURL: remote,
            headCommit: head,
            isDirty: isDirty,
            aheadCount: ahead,
            behindCount: behind
        )
    }

    /// Get the current branch name
    public func getCurrentBranch() async throws -> String {
        let output = try await runGit("branch", "--show-current")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the remote URL for origin
    public func getRemoteURL() async throws -> URL? {
        let output = try await runGit("remote", "get-url", "origin")
        let urlString = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: urlString)
    }

    /// Get the HEAD commit hash
    public func getHeadCommit() async throws -> String {
        let output = try await runGit("rev-parse", "--short", "HEAD")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get ahead/behind count relative to upstream
    public func getAheadBehind() async throws -> (ahead: Int, behind: Int) {
        let output = try await runGit("rev-list", "--left-right", "--count", "@{u}...HEAD")
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }

    // MARK: - Stage/Unstage

    /// Stage a file
    public func stage(_ path: String) async throws {
        _ = try await runGit("add", path)
    }

    /// Stage all changes
    public func stageAll() async throws {
        _ = try await runGit("add", "-A")
    }

    /// Unstage a file
    public func unstage(_ path: String) async throws {
        _ = try await runGit("reset", "HEAD", "--", path)
    }

    /// Unstage all changes
    public func unstageAll() async throws {
        _ = try await runGit("reset", "HEAD")
    }

    // MARK: - Commit

    /// Create a commit with the given message
    public func commit(message: String) async throws {
        _ = try await runGit("commit", "-m", message)
    }

    // MARK: - Discard

    /// Discard changes to a tracked file (revert to HEAD)
    public func discard(_ path: String) async throws {
        _ = try await runGit("checkout", "--", path)
    }

    /// Discard an untracked file (delete it)
    public func discardUntracked(_ path: String) async throws {
        _ = try await runGit("clean", "-f", "--", path)
    }

    /// Discard all changes (tracked files only)
    public func discardAll() async throws {
        _ = try await runGit("checkout", "--", ".")
    }

    /// Discard all untracked files
    public func discardAllUntracked() async throws {
        _ = try await runGit("clean", "-fd")
    }

    // MARK: - Diff

    /// Get the diff for a file
    public func diff(for path: String, staged: Bool) async throws -> String {
        if staged {
            return try await runGit("diff", "--cached", "--", path)
        } else {
            return try await runGit("diff", "--", path)
        }
    }

    // MARK: - Log

    /// Get recent commit log
    public func log(count: Int = 10) async throws -> [GitLogEntry] {
        let format = "--format=%H%n%h%n%an%n%ae%n%s%n%at%n---"
        let output = try await runGit("log", "-\(count)", format)
        return parseLogOutput(output)
    }

    private func parseLogOutput(_ output: String) -> [GitLogEntry] {
        var entries: [GitLogEntry] = []
        let commits = output.components(separatedBy: "---\n")

        for commit in commits where !commit.isEmpty {
            let lines = commit.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 6 else { continue }

            let hash = String(lines[0])
            let shortHash = String(lines[1])
            let authorName = String(lines[2])
            let authorEmail = String(lines[3])
            let message = String(lines[4])
            let timestamp = TimeInterval(lines[5]) ?? 0

            entries.append(GitLogEntry(
                hash: hash,
                shortHash: shortHash,
                authorName: authorName,
                authorEmail: authorEmail,
                message: message,
                date: Date(timeIntervalSince1970: timestamp)
            ))
        }

        return entries
    }

    // MARK: - Git Execution

    /// Run a git command and return the output
    private func runGit(_ arguments: String...) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Run git command with stdin input
    private func runGitWithStdin(_ arguments: [String], input: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        // Write input to stdin
        if let inputData = input.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(inputData)
        }
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Check for errors
        if process.terminationStatus != 0 && !output.isEmpty {
            throw GitError.commandFailed(output)
        }

        return output
    }

    // MARK: - Hunk Operations

    /// Stage a single hunk using a patch
    ///
    /// - Parameter patch: A valid unified diff patch string
    public func stageHunk(_ patch: String) async throws {
        _ = try await runGitWithStdin(["apply", "--cached", "-"], input: patch)
    }

    /// Unstage a single hunk (reverse apply from index)
    ///
    /// - Parameter patch: A valid unified diff patch string
    public func unstageHunk(_ patch: String) async throws {
        _ = try await runGitWithStdin(["apply", "--cached", "--reverse", "-"], input: patch)
    }

    /// Discard a single hunk from working directory
    ///
    /// - Parameter patch: A valid unified diff patch string
    public func discardHunk(_ patch: String) async throws {
        _ = try await runGitWithStdin(["apply", "--reverse", "-"], input: patch)
    }
}

// MARK: - Git Errors

public enum GitError: Error, LocalizedError {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return "Git command failed: \(output)"
        }
    }
}

// MARK: - Git Log Entry

/// A single git log entry
public struct GitLogEntry: Identifiable, Equatable, Sendable {
    public var id: String { hash }
    public let hash: String
    public let shortHash: String
    public let authorName: String
    public let authorEmail: String
    public let message: String
    public let date: Date

    public var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
