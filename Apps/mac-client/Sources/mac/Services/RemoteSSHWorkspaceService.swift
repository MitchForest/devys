import AppFeatures
import Foundation
import RemoteCore
import SSH

enum RemoteSSHWorkspaceError: LocalizedError {
    case missingSSHExecutable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSSHExecutable:
            return "The macOS `ssh` executable is unavailable."
        case .commandFailed(let message):
            return message
        }
    }
}

actor RemoteSSHWorkspaceService {
    private let sshExecutableURL: URL
    private let fileManager: FileManager
    private let operations: SSHRemoteWorkspaceOperations

    init(
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        fileManager: FileManager = .default,
        tmuxServerLabel: String = "devys"
    ) {
        self.sshExecutableURL = sshExecutableURL
        self.fileManager = fileManager
        self.operations = SSHRemoteWorkspaceOperations(tmuxServerLabel: tmuxServerLabel)
    }

    func refreshWorktrees(
        for repository: RemoteRepositoryAuthority
    ) async throws -> [RemoteWorktree] {
        try await operations.refreshWorktrees(repository: repository) { command in
            try await self.runRemoteShellCommand(
                target: repository.sshTarget,
                command: command
            )
        }
    }

    func createWorktree(
        repository: RemoteRepositoryAuthority,
        draft: RemoteWorktreeDraft
    ) async throws -> RemoteWorktree {
        try await operations.createWorktree(repository: repository, draft: draft) { command in
            try await self.runRemoteShellCommand(
                target: repository.sshTarget,
                command: command
            )
        }
    }

    func fetch(repository: RemoteRepositoryAuthority) async throws {
        try await operations.fetch(repository: repository) { command in
            try await self.runRemoteShellCommand(
                target: repository.sshTarget,
                command: command
            )
        }
    }

    func pull(
        repository: RemoteRepositoryAuthority,
        worktree: RemoteWorktree
    ) async throws {
        try await operations.pull(worktree: worktree) { command in
            try await self.runRemoteShellCommand(
                target: repository.sshTarget,
                command: command
            )
        }
    }

    func push(
        repository: RemoteRepositoryAuthority,
        worktree: RemoteWorktree
    ) async throws {
        try await operations.push(worktree: worktree) { command in
            try await self.runRemoteShellCommand(
                target: repository.sshTarget,
                command: command
            )
        }
    }

    func prepareShellLaunch(
        repository: RemoteRepositoryAuthority,
        worktree: RemoteWorktree
    ) async throws -> String {
        let preparedSession = try await operations.prepareShellSession(
            repository: repository,
            worktree: worktree
        ) { command in
            try await self.runRemoteShellCommand(
                target: repository.sshTarget,
                command: command
            )
        }

        return operations.makeAttachCommand(
            sshExecutablePath: sshExecutableURL.path,
            target: repository.sshTarget,
            sessionName: preparedSession.session.sessionName,
            workingDirectory: preparedSession.session.remotePath
        )
    }
}

private extension RemoteSSHWorkspaceService {
    func runRemoteShellCommand(
        target: String,
        command: String
    ) async throws -> String {
        guard fileManager.isExecutableFile(atPath: sshExecutableURL.path) else {
            throw RemoteSSHWorkspaceError.missingSSHExecutable
        }

        let process = Process()
        process.executableURL = sshExecutableURL
        process.arguments = [
            "-o", "BatchMode=yes",
            target,
            "sh -lc \(shellEscape(command))"
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = [trimmedError, trimmedOutput]
                        .first { !$0.isEmpty }
                        ?? "Remote command failed with exit status \(process.terminationStatus)."
                    continuation.resume(
                        throwing: RemoteSSHWorkspaceError.commandFailed(message)
                    )
                    return
                }

                continuation.resume(returning: stdout)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    throwing: RemoteSSHWorkspaceError.commandFailed(error.localizedDescription)
                )
            }
        }
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
