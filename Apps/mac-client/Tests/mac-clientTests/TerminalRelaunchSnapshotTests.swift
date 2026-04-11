import ACPClientKit
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Terminal Relaunch Snapshot Tests")
struct TerminalRelaunchSnapshotTests {
    @Test("Workspace relaunch snapshots round-trip editor, diff, terminal, and agent tabs")
    func snapshotRoundTrip() throws {
        let repositoryURL = URL(fileURLWithPath: "/tmp/devys/repo")
        let editorURL = URL(fileURLWithPath: "/tmp/devys/repo/README.md")
        let workspaceID = "/tmp/devys/repo/worktrees/feature"
        let terminalID = UUID()
        let snapshot = TerminalRelaunchSnapshot(
            repositoryRootURLs: [repositoryURL],
            selectedRepositoryID: Repository(rootURL: repositoryURL).id,
            selectedWorkspaceID: workspaceID,
            hostedSessions: [
                HostedTerminalSessionRecord(
                    id: terminalID,
                    workspaceID: workspaceID,
                    workingDirectory: repositoryURL,
                    launchCommand: "npm run dev",
                    createdAt: Date(timeIntervalSince1970: 100)
                )
            ],
            workspaceStates: [
                PersistedWorkspaceLayoutState(
                    workspaceID: workspaceID,
                    sidebarMode: .changes,
                    tree: .pane(
                        selectedTabIndex: 2,
                        tabs: [
                            .editor(fileURL: editorURL),
                            .gitDiff(path: "README.md", isStaged: false),
                            .terminal(hostedSessionID: terminalID),
                            .agent(
                                PersistedAgentSessionRecord(
                                    sessionID: "session-1",
                                    kind: .codex,
                                    title: "Codex",
                                    subtitle: "Restored"
                                )
                            )
                        ]
                    )
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalRelaunchSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.hasRepositories)
    }

    @Test("Empty snapshots report no repositories")
    func emptySnapshotHasNoRepositories() {
        #expect(!TerminalRelaunchSnapshot.empty.hasRepositories)
    }

    @Test("Workspace layout snapshots keep restore state isolated per workspace")
    func workspaceLayoutIsolation() throws {
        let snapshot = makeWorkspaceIsolationSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TerminalRelaunchSnapshot.self, from: data)

        #expect(decoded.selectedWorkspaceID == "/tmp/devys/repo/worktrees/feature-b")
        #expect(
            Set(decoded.workspaceStates.map(\.workspaceID)) ==
                Set(["/tmp/devys/repo/worktrees/feature-a", "/tmp/devys/repo/worktrees/feature-b"])
        )
        #expect(
            decoded.workspaceStates.first { $0.workspaceID == "/tmp/devys/repo/worktrees/feature-a" }?.sidebarMode ==
                .files
        )
        #expect(
            decoded.workspaceStates.first { $0.workspaceID == "/tmp/devys/repo/worktrees/feature-b" }?.sidebarMode ==
                .changes
        )
    }

    private func makeWorkspaceIsolationSnapshot() -> TerminalRelaunchSnapshot {
        let repositoryURL = URL(fileURLWithPath: "/tmp/devys/repo")
        let sharedEditorURL = repositoryURL.appendingPathComponent("Sources/App.swift")
        let firstWorkspaceID = "/tmp/devys/repo/worktrees/feature-a"
        let secondWorkspaceID = "/tmp/devys/repo/worktrees/feature-b"
        let firstTerminalID = UUID()
        let secondTerminalID = UUID()
        let hostedSessions = [
            hostedSession(
                id: firstTerminalID,
                workspaceID: firstWorkspaceID,
                repositoryURL: repositoryURL,
                command: "npm run dev",
                createdAt: 100
            ),
            hostedSession(
                id: secondTerminalID,
                workspaceID: secondWorkspaceID,
                repositoryURL: repositoryURL,
                command: "npm test",
                createdAt: 200
            )
        ]
        let workspaceStates = [
            workspaceLayoutState(
                workspaceID: firstWorkspaceID,
                sidebarMode: .files,
                editorURL: sharedEditorURL,
                diffIsStaged: false,
                terminalID: firstTerminalID,
                selectedTabIndex: 0
            ),
            workspaceLayoutState(
                workspaceID: secondWorkspaceID,
                sidebarMode: .changes,
                editorURL: sharedEditorURL,
                diffIsStaged: true,
                terminalID: secondTerminalID,
                selectedTabIndex: 1
            )
        ]

        return TerminalRelaunchSnapshot(
            repositoryRootURLs: [repositoryURL],
            selectedRepositoryID: Repository(rootURL: repositoryURL).id,
            selectedWorkspaceID: secondWorkspaceID,
            hostedSessions: hostedSessions,
            workspaceStates: workspaceStates
        )
    }

    private func hostedSession(
        id: UUID,
        workspaceID: Workspace.ID,
        repositoryURL: URL,
        command: String,
        createdAt: TimeInterval
    ) -> HostedTerminalSessionRecord {
        HostedTerminalSessionRecord(
            id: id,
            workspaceID: workspaceID,
            workingDirectory: repositoryURL,
            launchCommand: command,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func workspaceLayoutState(
        workspaceID: Workspace.ID,
        sidebarMode: WorkspaceSidebarMode,
        editorURL: URL,
        diffIsStaged: Bool,
        terminalID: UUID,
        selectedTabIndex: Int
    ) -> PersistedWorkspaceLayoutState {
        PersistedWorkspaceLayoutState(
            workspaceID: workspaceID,
            sidebarMode: sidebarMode,
            tree: .pane(
                selectedTabIndex: selectedTabIndex,
                tabs: [
                    .editor(fileURL: editorURL),
                    .gitDiff(path: "Sources/App.swift", isStaged: diffIsStaged),
                    .terminal(hostedSessionID: terminalID),
                    .agent(
                        PersistedAgentSessionRecord(
                            sessionID: "session-\(workspaceID)",
                            kind: .claude,
                            title: "Claude",
                            subtitle: "Connected"
                        )
                    )
                ]
            )
        )
    }
}
