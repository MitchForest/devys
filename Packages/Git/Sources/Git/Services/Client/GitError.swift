// GitError.swift
// Typed errors for git operations.

import Foundation

/// Errors from git CLI operations.
enum GitError: Error, LocalizedError, Sendable {
    case notRepository(URL)
    case commandFailed(arguments: [String], stderr: String, stdout: String, status: Int32)
    case timedOut(arguments: [String], timeout: TimeInterval)
    case invalidOutput(String)
    
    var errorDescription: String? {
        switch self {
        case .notRepository(let url):
            return "No Git repository found at \(url.path)."
            
        case .commandFailed(let arguments, let stderr, let stdout, let status):
            let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmedStderr.isEmpty ? trimmedStdout : trimmedStderr
            let fallback = message.isEmpty ? "Exit status \(status)" : message
            return "Git command failed (\(arguments.joined(separator: " "))): \(fallback)"
            
        case .timedOut(let arguments, let timeout):
            let duration = String(format: "%.1f", timeout)
            return "Git command timed out after \(duration)s (\(arguments.joined(separator: " ")))."
            
        case .invalidOutput(let message):
            return "Invalid git output: \(message)"
        }
    }
    
}

/// Errors from GitHub CLI operations.
enum PRError: Error, LocalizedError, Sendable {
    case notFound(Int)
    case ghNotInstalled
    case notAuthenticated
    case rateLimited
    case commandFailed(arguments: [String], stderr: String, status: Int32)
    
    var errorDescription: String? {
        switch self {
        case .notFound(let number):
            return "PR #\(number) not found."
        case .ghNotInstalled:
            return "GitHub CLI (gh) is not installed. Install from https://cli.github.com"
        case .notAuthenticated:
            return "Not authenticated with GitHub. Run 'gh auth login' in terminal."
        case .rateLimited:
            return "GitHub API rate limit exceeded. Try again later."
        case .commandFailed(let args, let stderr, _):
            return "gh \(args.joined(separator: " ")): \(stderr)"
        }
    }
}
