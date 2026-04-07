// GitClient+StatusHelpers.swift
// Shared parsing helpers for working tree and upstream status.

import Foundation

extension GitClient {
    func statusSummary() async throws -> WorktreeStatusSummary {
        let output = try await runGit("status", "--porcelain=v1")
        return parseStatusSummary(output)
    }

    func getUpstreamBranch() async throws -> String? {
        let output = try await runGit("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func parseStatusChar(_ char: String) -> GitFileStatus? {
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

    // periphery:ignore - helper for explicit ignored-aware status expansion only
    func ignoredPaths() async throws -> [String] {
        let output = try await runGit("ls-files", "--others", "-i", "--exclude-standard")
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func parseStatusSummary(_ output: String) -> WorktreeStatusSummary {
        var staged = 0
        var unstaged = 0
        var untracked = 0
        var conflicts = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.count >= 2 else { continue }

            let lineStr = String(line)
            let indexStatus = String(lineStr.prefix(1))
            let worktreeStatus = String(lineStr.dropFirst(1).prefix(1))

            if indexStatus == "?" && worktreeStatus == "?" {
                untracked += 1
                continue
            }

            if indexStatus == "U" || worktreeStatus == "U" {
                conflicts += 1
                continue
            }

            if indexStatus != " ", indexStatus != "?" {
                staged += 1
            }

            if worktreeStatus != " " {
                unstaged += 1
            }
        }

        return WorktreeStatusSummary(
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
            conflicts: conflicts
        )
    }
}
