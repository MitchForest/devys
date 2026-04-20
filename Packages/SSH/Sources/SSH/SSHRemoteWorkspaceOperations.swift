import Foundation
import RemoteCore

public struct SSHRemoteWorkspaceOperations: Sendable {
    public typealias RemoteCommandRunner = @Sendable (String) async throws -> String

    public var tmuxServerLabel: String

    public init(tmuxServerLabel: String = "devys") {
        self.tmuxServerLabel = tmuxServerLabel
    }

    public func refreshWorktrees(
        repository: RemoteRepositoryAuthority,
        runRemoteCommand: RemoteCommandRunner
    ) async throws -> [RemoteWorktree] {
        let output = try await runRemoteCommand(
            "cd \(shellEscape(repository.repositoryPath)) && git worktree list --porcelain"
        )

        let entries = RemoteGitWorktreeListParser.parse(output)
        var worktrees: [RemoteWorktree] = []
        for entry in entries {
            let branchName = entry.branchName ?? URL(fileURLWithPath: entry.path).lastPathComponent
            let status = try await loadWorktreeStatus(
                remotePath: entry.path,
                runRemoteCommand: runRemoteCommand
            )
            let headSHA = try? await runRemoteCommand(
                "cd \(shellEscape(entry.path)) && git rev-parse HEAD"
            )
            worktrees.append(
                RemoteWorktree(
                    repositoryID: repository.id,
                    branchName: branchName,
                    remotePath: entry.path,
                    detail: URL(fileURLWithPath: entry.path).lastPathComponent,
                    isPrimary: normalizeRemotePath(entry.path) == normalizeRemotePath(repository.repositoryPath),
                    headSHA: headSHA?.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: status
                )
            )
        }

        return worktrees.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }
            return lhs.branchName.localizedStandardCompare(rhs.branchName) == .orderedAscending
        }
    }

    public func createWorktree(
        repository: RemoteRepositoryAuthority,
        draft: RemoteWorktreeDraft,
        runRemoteCommand: RemoteCommandRunner
    ) async throws -> RemoteWorktree {
        let branchName = draft.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else {
            throw SSHRemoteWorkspaceError.invalidBranchName
        }

        let startPoint = draft.startPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let directoryName = draft.directoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDirectoryName = directoryName.isEmpty
            ? RemoteSessionNaming.defaultRemoteDirectoryName(
                repositoryName: repository.displayName,
                branchName: branchName
            )
            : directoryName
        let parentPath = (repository.repositoryPath as NSString).deletingLastPathComponent
        let remoteWorktreePath = normalizeRemotePath(
            (parentPath as NSString).appendingPathComponent(resolvedDirectoryName)
        )

        let branchExists = try await remoteBranchExists(
            repositoryPath: repository.repositoryPath,
            branchName: branchName,
            runRemoteCommand: runRemoteCommand
        )

        let addCommand: String
        if branchExists {
            addCommand = """
            cd \(shellEscape(repository.repositoryPath)) && \
            git worktree add \(shellEscape(remoteWorktreePath)) \(shellEscape(branchName))
            """
        } else {
            let resolvedStartPoint = startPoint.isEmpty ? "origin/main" : startPoint
            addCommand = """
            cd \(shellEscape(repository.repositoryPath)) && \
            git worktree add -b \(shellEscape(branchName)) \(shellEscape(remoteWorktreePath)) \
            \(shellEscape(resolvedStartPoint))
            """
        }

        _ = try await runRemoteCommand(addCommand)

        let worktrees = try await refreshWorktrees(
            repository: repository,
            runRemoteCommand: runRemoteCommand
        )
        if let created = worktrees.first(where: { $0.remotePath == remoteWorktreePath }) {
            return created
        }

        throw SSHRemoteWorkspaceError.commandFailed(
            "Created remote worktree but could not rediscover it at \(remoteWorktreePath)."
        )
    }

    public func fetch(
        repository: RemoteRepositoryAuthority,
        runRemoteCommand: RemoteCommandRunner
    ) async throws {
        _ = try await runRemoteCommand(
            "cd \(shellEscape(repository.repositoryPath)) && git fetch origin"
        )
    }

    public func pull(
        worktree: RemoteWorktree,
        runRemoteCommand: RemoteCommandRunner
    ) async throws {
        _ = try await runRemoteCommand(
            "cd \(shellEscape(worktree.remotePath)) && git pull --ff-only"
        )
    }

    public func push(
        worktree: RemoteWorktree,
        runRemoteCommand: RemoteCommandRunner
    ) async throws {
        _ = try await runRemoteCommand(
            "cd \(shellEscape(worktree.remotePath)) && git push"
        )
    }

    public func prepareShellSession(
        repository: RemoteRepositoryAuthority,
        worktree: RemoteWorktree,
        runRemoteCommand: RemoteCommandRunner
    ) async throws -> SSHRemotePreparedShellSession {
        let session = shellSession(repository: repository, worktree: worktree)
        _ = try await runRemoteCommand(
            makeShellBootstrapCommand(
                sessionName: session.sessionName,
                workingDirectory: worktree.remotePath
            )
        )
        return SSHRemotePreparedShellSession(
            session: session,
            remoteAttachCommand: makeRemoteAttachCommand(
                sessionName: session.sessionName,
                workingDirectory: worktree.remotePath
            )
        )
    }

    public func discoverShellSessions(
        repository: RemoteRepositoryAuthority,
        worktrees: [RemoteWorktree],
        runRemoteCommand: RemoteCommandRunner
    ) async throws -> [SSHRemoteShellSession] {
        let output = try await runRemoteCommand(
            """
            TMUX= tmux -L \(shellEscape(tmuxServerLabel)) list-sessions \
            -F '#{session_name}\t#{session_attached}\t#{session_created}' 2>/dev/null || true
            """
        )

        let tmuxSessionsByName = TmuxSessionListParser.parse(output)

        return worktrees.compactMap { worktree in
            let session = shellSession(repository: repository, worktree: worktree)
            guard let discovered = tmuxSessionsByName[session.sessionName] else {
                return nil
            }

            return SSHRemoteShellSession(
                repositoryID: session.repositoryID,
                worktreeID: session.worktreeID,
                branchName: session.branchName,
                remotePath: session.remotePath,
                sessionName: session.sessionName,
                attachedClientCount: discovered.attachedClientCount,
                createdAt: discovered.createdAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
            return lhs.branchName.localizedStandardCompare(rhs.branchName) == .orderedAscending
        }
    }

    public func makeAttachCommand(
        sshExecutablePath: String = "/usr/bin/ssh",
        target: String,
        sessionName: String,
        workingDirectory: String
    ) -> String {
        [
            shellEscape(sshExecutablePath),
            "-tt",
            "-o",
            "BatchMode=yes",
            shellEscape(target),
            shellEscape(makeRemoteAttachCommand(sessionName: sessionName, workingDirectory: workingDirectory)),
        ]
        .joined(separator: " ")
    }
}

private extension SSHRemoteWorkspaceOperations {
    func shellSession(
        repository: RemoteRepositoryAuthority,
        worktree: RemoteWorktree
    ) -> SSHRemoteShellSession {
        SSHRemoteShellSession(
            repositoryID: repository.id,
            worktreeID: worktree.id,
            branchName: worktree.branchName,
            remotePath: worktree.remotePath,
            sessionName: RemoteSessionNaming.shellSessionName(
                target: repository.sshTarget,
                remotePath: worktree.remotePath
            )
        )
    }

    func loadWorktreeStatus(
        remotePath: String,
        runRemoteCommand: RemoteCommandRunner
    ) async throws -> RemoteWorktreeStatus {
        let output = try await runRemoteCommand(
            "cd \(shellEscape(remotePath)) && git status --porcelain"
        )
        return RemoteWorktreeStatus(
            isDirty: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    func remoteBranchExists(
        repositoryPath: String,
        branchName: String,
        runRemoteCommand: RemoteCommandRunner
    ) async throws -> Bool {
        do {
            _ = try await runRemoteCommand(
                """
                cd \(shellEscape(repositoryPath)) && \
                git show-ref --verify --quiet \(shellEscape("refs/heads/\(branchName)"))
                """
            )
            return true
        } catch {
            return false
        }
    }

    func makeShellBootstrapCommand(
        sessionName: String,
        workingDirectory: String
    ) -> String {
        """
        if ! TMUX= tmux -L \(shellEscape(tmuxServerLabel)) has-session -t \(shellEscape(sessionName)) \
        2>/dev/null; then
          TMUX= tmux -L \(shellEscape(tmuxServerLabel)) new-session -d -s \(shellEscape(sessionName)) \
          -c \(shellEscape(workingDirectory))
        fi
        """
    }

    func makeRemoteAttachCommand(
        sessionName: String,
        workingDirectory: String
    ) -> String {
        let bootstrap = makeShellBootstrapCommand(
            sessionName: sessionName,
            workingDirectory: workingDirectory
        )
        let attach = "exec TMUX= tmux -L \(tmuxServerLabel) attach-session -t \(sessionName)"
        return "sh -lc \(shellEscape("\(bootstrap); \(attach)"))"
    }
}

private struct RemoteGitWorktreeEntry: Sendable {
    let path: String
    let branchRef: String?

    var branchName: String? {
        guard let branchRef else { return nil }
        if branchRef.hasPrefix("refs/heads/") {
            return String(branchRef.dropFirst("refs/heads/".count))
        }
        return branchRef
    }
}

private enum RemoteGitWorktreeListParser {
    static func parse(_ output: String) -> [RemoteGitWorktreeEntry] {
        var entries: [RemoteGitWorktreeEntry] = []
        var path: String?
        var branchRef: String?

        func appendCurrent() {
            guard let path else { return }
            entries.append(
                RemoteGitWorktreeEntry(
                    path: normalizeRemotePath(path),
                    branchRef: branchRef
                )
            )
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                appendCurrent()
                path = String(line.dropFirst("worktree ".count))
                branchRef = nil
                continue
            }
            if line.hasPrefix("branch ") {
                branchRef = String(line.dropFirst("branch ".count))
            }
        }

        appendCurrent()
        return entries
    }
}

private struct TmuxSessionRecord: Sendable, Equatable {
    let attachedClientCount: Int
    let createdAt: Date?
}

private enum TmuxSessionListParser {
    static func parse(_ output: String) -> [String: TmuxSessionRecord] {
        output
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: TmuxSessionRecord]()) { partialResult, rawLine in
                let line = String(rawLine)
                let fields = line.components(separatedBy: "\t")
                guard fields.count == 3 else { return }

                let attachedClientCount = Int(fields[1]) ?? 0
                let createdAt = TimeInterval(fields[2]).map(Date.init(timeIntervalSince1970:))
                partialResult[fields[0]] = TmuxSessionRecord(
                    attachedClientCount: attachedClientCount,
                    createdAt: createdAt
                )
            }
    }
}

private func normalizeRemotePath(_ path: String) -> String {
    RemoteSessionNaming.normalizedRemotePath(path)
}

private func shellEscape(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    if value.unicodeScalars.allSatisfy({ scalar in
        CharacterSet.alphanumerics.contains(scalar) || "/-._:=@".unicodeScalars.contains(scalar)
    }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
