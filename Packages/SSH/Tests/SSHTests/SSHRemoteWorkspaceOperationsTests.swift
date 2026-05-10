import RemoteCore
import SSH
import XCTest

final class SSHRemoteWorkspaceOperationsTests: XCTestCase {
    func testRefreshWorktreesParsesRemoteState() async throws {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let recorder = RemoteCommandRecorder(
            outputs: [
                "cd /Users/mitch/Code/devys && git worktree list --porcelain": """
                worktree /Users/mitch/Code/devys
                HEAD 1234567
                branch refs/heads/main

                worktree /Users/mitch/Code/devys-feature
                HEAD abcdef0
                branch refs/heads/feature/test
                """,
                "cd /Users/mitch/Code/devys && git status --porcelain": "",
                "cd /Users/mitch/Code/devys && git rev-parse HEAD": "1234567890\n",
                "cd /Users/mitch/Code/devys-feature && git status --porcelain": " M README.md\n",
                "cd /Users/mitch/Code/devys-feature && git rev-parse HEAD": "abcdef0123\n",
            ]
        )

        let worktrees = try await SSHRemoteWorkspaceOperations().refreshWorktrees(
            repository: repository,
            runRemoteCommand: { command in
                try await recorder.run(command)
            }
        )

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees[0].branchName, "main")
        XCTAssertTrue(worktrees[0].isPrimary)
        XCTAssertEqual(worktrees[0].headSHA, "1234567890")
        XCTAssertEqual(worktrees[1].branchName, "feature/test")
        XCTAssertFalse(worktrees[1].isPrimary)
        XCTAssertEqual(worktrees[1].headSHA, "abcdef0123")
        XCTAssertTrue(worktrees[1].status.isDirty)
    }

    func testCreateWorktreeUsesDefaultDirectoryNameAndRefreshes() async throws {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let draft = RemoteWorktreeDraft(
            repositoryID: repository.id,
            branchName: "feature/test"
        )
        let recorder = RemoteCommandRecorder(
            outputs: [
                """
                cd /Users/mitch/Code/devys && \
                git show-ref --verify --quiet refs/heads/feature/test
                """: "",
                """
                cd /Users/mitch/Code/devys && \
                git worktree add /Users/mitch/Code/devys-feature-test feature/test
                """: "",
                "cd /Users/mitch/Code/devys && git worktree list --porcelain": """
                worktree /Users/mitch/Code/devys
                HEAD 1234567
                branch refs/heads/main

                worktree /Users/mitch/Code/devys-feature-test
                HEAD abcdef0
                branch refs/heads/feature/test
                """,
                "cd /Users/mitch/Code/devys && git status --porcelain": "",
                "cd /Users/mitch/Code/devys && git rev-parse HEAD": "1234567890\n",
                "cd /Users/mitch/Code/devys-feature-test && git status --porcelain": "",
                "cd /Users/mitch/Code/devys-feature-test && git rev-parse HEAD": "abcdef0123\n",
            ]
        )

        let created = try await SSHRemoteWorkspaceOperations().createWorktree(
            repository: repository,
            draft: draft,
            runRemoteCommand: { command in
                try await recorder.run(command)
            }
        )

        XCTAssertEqual(created.branchName, "feature/test")
        XCTAssertEqual(created.remotePath, "/Users/mitch/Code/devys-feature-test")
    }

    func testPrepareShellSessionBootstrapsTmuxSession() async throws {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let worktree = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "feature/test",
            remotePath: "/Users/mitch/Code/devys-feature-test",
            isPrimary: false
        )
        let recorder = RemoteCommandRecorder(outputs: [:], defaultOutput: "")
        let operations = SSHRemoteWorkspaceOperations()

        let prepared = try await operations.prepareShellSession(
            repository: repository,
            worktree: worktree,
            runRemoteCommand: { command in
                try await recorder.run(command)
            }
        )

        XCTAssertEqual(
            prepared.session.sessionName,
            RemoteSessionNaming.shellSessionName(
                target: "mac-mini",
                remotePath: "/Users/mitch/Code/devys-feature-test"
            )
        )
        XCTAssertTrue(prepared.remoteAttachCommand.contains("attach-session"))
        XCTAssertTrue(prepared.remoteAttachCommand.contains(prepared.session.sessionName))
        let commands = await recorder.commands
        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0].contains("tmux -L devys new-session -d -s"))
        XCTAssertTrue(commands[0].contains("-c /Users/mitch/Code/devys-feature-test"))
    }

    func testDiscoverShellSessionsMatchesDeterministicWorktreeSessions() async throws {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let primary = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "main",
            remotePath: "/Users/mitch/Code/devys",
            isPrimary: true
        )
        let feature = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "feature/test",
            remotePath: "/Users/mitch/Code/devys-feature-test",
            isPrimary: false
        )
        let orphanSessionName = RemoteSessionNaming.shellSessionName(
            target: "mac-mini",
            remotePath: "/tmp/other"
        )
        let recorder = RemoteCommandRecorder(
            outputs: [
                """
                TMUX= tmux -L devys list-sessions \
                -F '#{session_name}\t#{session_attached}\t#{session_created}' 2>/dev/null || true
                """: """
                \(RemoteSessionNaming.shellSessionName(target: repository.sshTarget, remotePath: feature.remotePath))\t2\t1710000000
                \(orphanSessionName)\t1\t1711000000
                \(RemoteSessionNaming.shellSessionName(target: repository.sshTarget, remotePath: primary.remotePath))\t0\t1700000000
                """
            ]
        )

        let sessions = try await SSHRemoteWorkspaceOperations().discoverShellSessions(
            repository: repository,
            worktrees: [primary, feature],
            runRemoteCommand: { command in
                try await recorder.run(command)
            }
        )

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].worktreeID, feature.id)
        XCTAssertEqual(sessions[0].attachedClientCount, 2)
        XCTAssertEqual(sessions[1].worktreeID, primary.id)
        XCTAssertEqual(sessions[1].attachedClientCount, 0)
    }
}

private actor RemoteCommandRecorder {
    private let outputs: [String: String]
    private let defaultOutput: String?
    private(set) var commands: [String] = []

    init(
        outputs: [String: String],
        defaultOutput: String? = nil
    ) {
        self.outputs = outputs
        self.defaultOutput = defaultOutput
    }

    func run(_ command: String) throws -> String {
        commands.append(command)
        if let output = outputs[command] {
            return output
        }
        if let defaultOutput {
            return defaultOutput
        }
        throw RecorderError.unexpectedCommand(command)
    }
}

private enum RecorderError: Error, LocalizedError {
    case unexpectedCommand(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedCommand(let command):
            return "Unexpected command: \(command)"
        }
    }
}
