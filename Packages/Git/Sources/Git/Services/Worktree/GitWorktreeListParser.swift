// GitWorktreeListParser.swift
// Parser for `git worktree list --porcelain` output.

import Foundation

struct GitWorktreeEntry: Equatable, Sendable {
    let path: URL
    let branchRef: String?
    let createdAt: Date?

    var branchName: String? {
        guard let branchRef else { return nil }
        if branchRef.hasPrefix("refs/heads/") {
            return String(branchRef.dropFirst("refs/heads/".count))
        }
        if branchRef.hasPrefix("refs/") {
            return String(branchRef.dropFirst("refs/".count))
        }
        return branchRef
    }
}

enum GitWorktreeListParser {
    static func parse(_ output: String) -> [GitWorktreeEntry] {
        var entries: [GitWorktreeEntry] = []
        var builder: Builder?

        for rawLine in output.split(whereSeparator: \Character.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                if let builder {
                    entries.append(builder.build())
                }
                let path = String(line.dropFirst("worktree ".count))
                builder = Builder(path: URL(fileURLWithPath: path))
                continue
            }
            builder?.apply(line: line)
        }

        if let builder {
            entries.append(builder.build())
        }

        return entries
    }

    private struct Builder {
        let path: URL
        var branchRef: String?

        mutating func apply(line: String) {
            if line.hasPrefix("branch ") {
                branchRef = String(line.dropFirst("branch ".count))
                return
            }
        }

        func build() -> GitWorktreeEntry {
            GitWorktreeEntry(
                path: path,
                branchRef: branchRef,
                createdAt: nil
            )
        }
    }
}
