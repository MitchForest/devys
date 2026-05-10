import Diff
import Foundation

public actor GitClient {
    private let repositoryURL: URL
    private let runner: GitCommandRunner
    private let fileDiscarder: GitFileDiscarder

    public init(
        repositoryURL: URL,
        fileDiscarder: GitFileDiscarder = .removeImmediately
    ) {
        self.repositoryURL = repositoryURL.standardizedFileURL
        self.runner = GitCommandRunner(repositoryURL: self.repositoryURL)
        self.fileDiscarder = fileDiscarder
    }

    public func status() async throws -> [GitFileChange] {
        do {
            let output = try await runner.run(arguments: ["status", "--porcelain=v1"])
            return GitStatusParser.parse(output)
        } catch GitError.commandFailed(let message)
            where message.localizedCaseInsensitiveContains("not a git repository") {
            throw GitError.notRepository
        }
    }

    public func diff(
        for change: GitFileChange,
        contextLines: Int = 3,
        ignoreWhitespace: Bool = false
    ) async throws -> String {
        var arguments = ["diff", "--no-color", "--unified=\(contextLines)"]
        if ignoreWhitespace {
            arguments.append("-w")
        }
        if change.isStaged {
            arguments.append("--cached")
        }
        arguments += ["--", change.path]
        return try await runner.run(arguments: arguments)
    }

    public func diffSnapshot(
        for change: GitFileChange,
        contextLines: Int = 3,
        ignoreWhitespace: Bool = false
    ) async throws -> DiffSnapshot {
        if change.status == .untracked {
            return try await untrackedDiffSnapshot(path: change.path)
        }

        let diffText = try await diff(
            for: change,
            contextLines: contextLines,
            ignoreWhitespace: ignoreWhitespace
        )
        let parsedDiff = DiffParser.parse(diffText)
        guard !parsedDiff.isBinary else {
            return DiffSnapshot(from: parsedDiff)
        }

        let sourceRequest = makeDiffSourceContentRequest(
            parsedDiff: parsedDiff,
            change: change
        )
        async let baseContent = content(source: sourceRequest.base)
        async let modifiedContent = content(source: sourceRequest.modified)
        return try await DiffSnapshot(
            from: parsedDiff,
            baseContent: baseContent,
            modifiedContent: modifiedContent
        )
    }

    public func stageFile(_ change: GitFileChange) async throws {
        guard change.status != .ignored, change.status != .unmerged else {
            throw GitError.unsupportedOperation("This file cannot be staged automatically.")
        }
        try await runGit(arguments: ["add", "--", change.path])
    }

    public func unstageFile(_ change: GitFileChange) async throws {
        guard change.isStaged else { return }
        do {
            try await runGit(arguments: ["restore", "--staged", "--", change.path])
        } catch GitError.commandFailed {
            try await runGit(arguments: ["reset", "HEAD", "--", change.path])
        }
    }

    public func discardFile(_ change: GitFileChange) async throws {
        guard change.status != .ignored, change.status != .unmerged else {
            throw GitError.unsupportedOperation("This file cannot be discarded automatically.")
        }

        if change.isStaged {
            throw GitError.unsupportedOperation("Unstage this file before discarding it.")
        }

        if change.status == .untracked {
            try await discardWorkingTreeItem(path: change.path)
            return
        }

        try await trashCurrentWorkingTreeItemIfPresent(path: change.path, preservingOriginal: false)
        try await runGit(arguments: ["restore", "--worktree", "--", change.path])
    }

    public func stageHunk(_ hunk: DiffHunk, for change: GitFileChange) async throws {
        guard !change.isStaged else { return }
        try await applyPatch(GitPatchBuilder.patch(for: hunk, change: change), cached: true, reverse: false)
    }

    public func unstageHunk(_ hunk: DiffHunk, for change: GitFileChange) async throws {
        guard change.isStaged else { return }
        try await applyPatch(GitPatchBuilder.patch(for: hunk, change: change), cached: true, reverse: true)
    }

    public func discardHunk(_ hunk: DiffHunk, for change: GitFileChange) async throws {
        guard change.status != .untracked else {
            throw GitError.unsupportedOperation("Discard the whole untracked file instead.")
        }
        try await trashCurrentWorkingTreeItemIfPresent(path: change.path, preservingOriginal: true)
        if change.isStaged {
            try await unstageHunk(hunk, for: change)
        }
        try await applyPatch(GitPatchBuilder.patch(for: hunk, change: change), cached: false, reverse: true)
    }

    private func applyPatch(_ patch: String, cached: Bool, reverse: Bool) async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("patch")
        try patch.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var arguments = ["apply", "--unidiff-zero"]
        if cached {
            arguments.append("--cached")
        }
        if reverse {
            arguments.append("--reverse")
        }
        arguments.append(tempFile.path)
        try await runGit(arguments: arguments)
    }

    private func runGit(arguments: [String]) async throws {
        _ = try await runner.run(arguments: arguments)
    }

    private func discardWorkingTreeItem(path: String) async throws {
        let url = repositoryURL.appendingPathComponent(path).standardizedFileURL
        try await fileDiscarder.discard(url)
    }

    private func trashCurrentWorkingTreeItemIfPresent(path: String, preservingOriginal: Bool) async throws {
        let url = repositoryURL.appendingPathComponent(path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if preservingOriginal {
            let backupDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("devys-git-discard-backups-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backupURL = backupDirectory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: backupURL)
            try await fileDiscarder.discard(backupURL)
        } else {
            try await fileDiscarder.discard(url)
        }
    }

    private enum DiffContentSource: Sendable, Equatable {
        case gitObject(String)
        case workingTree(String)
        case empty
    }

    private struct DiffSourceContentRequest: Sendable, Equatable {
        let base: DiffContentSource
        let modified: DiffContentSource
    }

    private func makeDiffSourceContentRequest(
        parsedDiff: ParsedDiff,
        change: GitFileChange
    ) -> DiffSourceContentRequest {
        let oldPath = parsedDiff.oldPath ?? change.previousPath ?? change.path
        let newPath = parsedDiff.newPath ?? change.path

        if change.isStaged {
            return DiffSourceContentRequest(
                base: parsedDiff.oldPath == nil ? .empty : .gitObject("HEAD:\(oldPath)"),
                modified: parsedDiff.newPath == nil ? .empty : .gitObject(":\(newPath)")
            )
        }

        return DiffSourceContentRequest(
            base: parsedDiff.oldPath == nil ? .empty : .gitObject(":\(oldPath)"),
            modified: parsedDiff.newPath == nil ? .empty : .workingTree(newPath)
        )
    }

    private func content(source: DiffContentSource) async throws -> String? {
        switch source {
        case .empty:
            nil
        case .gitObject(let specifier):
            try await gitObjectContent(specifier: specifier)
        case .workingTree(let path):
            try await workingTreeContent(path: path)
        }
    }

    private func gitObjectContent(specifier: String) async throws -> String? {
        do {
            let data = try await runner.runData(arguments: ["show", specifier])
            return String(data: data, encoding: .utf8)
        } catch GitError.commandFailed {
            return nil
        }
    }

    private func workingTreeContent(path: String) async throws -> String? {
        let fileURL = repositoryURL.appendingPathComponent(path)
        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            let data = try Data(contentsOf: fileURL)
            return String(data: data, encoding: .utf8)
        }.value
    }

    private func untrackedDiffSnapshot(path: String) async throws -> DiffSnapshot {
        let fileURL = repositoryURL.appendingPathComponent(path)
        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: fileURL)
        }.value

        guard !data.contains(0),
              let content = String(data: data, encoding: .utf8) else {
            return DiffSnapshot(from: ParsedDiff(
                hunks: [],
                isBinary: true,
                oldPath: nil,
                newPath: path
            ))
        }

        let lines = content.components(separatedBy: "\n")
        let displayLines = content.hasSuffix("\n") ? Array(lines.dropLast()) : lines
        let hunkLines = displayLines.enumerated().map { index, line in
            DiffLine(
                id: "\(path):untracked:\(index)",
                type: .added,
                content: line,
                oldLineNumber: nil,
                newLineNumber: index + 1
            )
        }
        let hunk = DiffHunk(
            id: "\(path):untracked:hunk",
            header: "@@ -0,0 +1,\(max(displayLines.count, 1)) @@",
            lines: hunkLines,
            oldStart: 0,
            oldCount: 0,
            newStart: 1,
            newCount: displayLines.count
        )
        let parsedDiff = ParsedDiff(
            hunks: displayLines.isEmpty ? [] : [hunk],
            isBinary: false,
            oldPath: nil,
            newPath: path
        )
        return DiffSnapshot(
            from: parsedDiff,
            baseContent: nil,
            modifiedContent: content
        )
    }
}
