import Foundation
import RemoteCore

public enum SSHRemoteWorkspaceError: LocalizedError, Sendable {
    case invalidBranchName
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBranchName:
            "A remote worktree requires a branch name."
        case .commandFailed(let message):
            message
        }
    }
}

public actor SSHRemoteWorkspaceService {
    private let commandClient: SSHCommandClient
    private let operations: SSHRemoteWorkspaceOperations

    public init(
        commandClient: SSHCommandClient = SSHCommandClient(),
        tmuxServerLabel: String = "devys"
    ) {
        self.commandClient = commandClient
        self.operations = SSHRemoteWorkspaceOperations(tmuxServerLabel: tmuxServerLabel)
    }

    public func refreshWorktrees(
        repository: RemoteRepositoryAuthority,
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws -> [RemoteWorktree] {
        try await operations.refreshWorktrees(repository: repository) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }

    public func createWorktree(
        repository: RemoteRepositoryAuthority,
        draft: RemoteWorktreeDraft,
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws -> RemoteWorktree {
        try await operations.createWorktree(repository: repository, draft: draft) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }

    public func fetch(
        repository: RemoteRepositoryAuthority,
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws {
        try await operations.fetch(repository: repository) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }

    public func pull(
        worktree: RemoteWorktree,
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws {
        try await operations.pull(worktree: worktree) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }

    public func push(
        worktree: RemoteWorktree,
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws {
        try await operations.push(worktree: worktree) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }

    public func prepareShellSession(
        repository: RemoteRepositoryAuthority,
        worktree: RemoteWorktree,
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws -> SSHRemotePreparedShellSession {
        try await operations.prepareShellSession(repository: repository, worktree: worktree) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }

    public func validateShellConnection(
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws {
        _ = try await runRemoteShellCommand(
            connection: connection,
            command: "true",
            hostKeyValidator: hostKeyValidator
        )
    }

    public func discoverShellSessions(
        repository: RemoteRepositoryAuthority,
        worktrees: [RemoteWorktree],
        connection: SSHConnectionConfiguration,
        hostKeyValidator: SSHCommandClient.HostKeyValidator? = nil
    ) async throws -> [SSHRemoteShellSession] {
        try await operations.discoverShellSessions(repository: repository, worktrees: worktrees) { command in
            try await self.runRemoteShellCommand(
                connection: connection,
                command: command,
                hostKeyValidator: hostKeyValidator
            )
        }
    }
}

private extension SSHRemoteWorkspaceService {
    func runRemoteShellCommand(
        connection: SSHConnectionConfiguration,
        command: String,
        hostKeyValidator: SSHCommandClient.HostKeyValidator?
    ) async throws -> String {
        let result = try await commandClient.run(
            configuration: connection,
            command: "sh -lc \(shellEscape(command))",
            hostKeyValidator: hostKeyValidator
        )
        guard result.exitStatus == 0 else {
            let trimmedError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedOutput = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = [trimmedError, trimmedOutput]
                .first { !$0.isEmpty }
                ?? "Remote command failed with exit status \(result.exitStatus)."
            throw SSHRemoteWorkspaceError.commandFailed(message)
        }
        return result.stdout
    }
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
