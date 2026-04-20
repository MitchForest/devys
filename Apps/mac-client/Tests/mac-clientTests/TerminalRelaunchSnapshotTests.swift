import ACPClientKit
import AppFeatures
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Terminal Relaunch Snapshot Tests")
struct TerminalRelaunchSnapshotTests {
    @Test("Workspace relaunch snapshots round-trip editor, diff, terminal, and chat tabs")
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
                    sidebarMode: .files,
                    tree: .pane(
                        selectedTabIndex: 2,
                        tabs: [
                            .editor(fileURL: editorURL),
                            .gitDiff(path: "README.md", isStaged: false),
                            .terminal(hostedSessionID: terminalID),
                            .chat(
                                PersistedChatSessionRecord(
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
                .agents
        )
    }

    @Test("Nested split workspace layout snapshots round-trip reducer-owned topology")
    func nestedSplitWorkspaceLayoutRoundTrip() throws {
        let repositoryURL = URL(fileURLWithPath: "/tmp/devys/repo")
        let workspaceID = "/tmp/devys/repo/worktrees/feature"
        let terminalID = UUID()
        let state = PersistedWorkspaceLayoutState(
            workspaceID: workspaceID,
            sidebarMode: .files,
            tree: .split(
                orientation: "horizontal",
                dividerPosition: 0.64,
                first: .pane(
                    selectedTabIndex: 0,
                    tabs: [.editor(fileURL: repositoryURL.appendingPathComponent("README.md"))]
                ),
                second: .split(
                    orientation: "vertical",
                    dividerPosition: 0.35,
                    first: .pane(
                        selectedTabIndex: 0,
                        tabs: [.terminal(hostedSessionID: terminalID)]
                    ),
                    second: .pane(
                        selectedTabIndex: 1,
                        tabs: [
                            .gitDiff(path: "README.md", isStaged: false),
                            .chat(
                                PersistedChatSessionRecord(
                                    sessionID: "session-nested",
                                    kind: .codex,
                                    title: "Nested",
                                    subtitle: "Reducer Layout"
                                )
                            )
                        ]
                    )
                )
            )
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedWorkspaceLayoutState.self, from: data)

        #expect(decoded == state)
    }

    @Test("Legacy changes and ports sidebar snapshots restore into the files tab")
    func legacySidebarModesDecodeIntoFilesTab() throws {
        let changesData = try JSONEncoder().encode(
            LegacyPersistedWorkspaceLayoutState(
                workspaceID: "/tmp/devys/repo/worktrees/feature-a",
                sidebarMode: "changes",
                tree: .pane(selectedTabIndex: 0, tabs: [])
            )
        )
        let portsData = try JSONEncoder().encode(
            LegacyPersistedWorkspaceLayoutState(
                workspaceID: "/tmp/devys/repo/worktrees/feature-b",
                sidebarMode: "ports",
                tree: .pane(selectedTabIndex: 0, tabs: [])
            )
        )

        let decodedChanges = try JSONDecoder().decode(PersistedWorkspaceLayoutState.self, from: changesData)
        let decodedPorts = try JSONDecoder().decode(PersistedWorkspaceLayoutState.self, from: portsData)

        #expect(decodedChanges.sidebarMode == .files)
        #expect(decodedPorts.sidebarMode == .files)
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
                sidebarMode: .agents,
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
        sidebarMode: PersistedWorkspaceSidebarMode,
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
                    .chat(
                        PersistedChatSessionRecord(
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

    private struct LegacyPersistedWorkspaceLayoutState: Encodable {
        let workspaceID: Workspace.ID
        let sidebarMode: String
        let tree: PersistedWorkspaceLayoutTree

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(workspaceID, forKey: .workspaceID)
            try container.encode(sidebarMode, forKey: .sidebarMode)
            try container.encode(tree, forKey: .tree)
        }

        private enum CodingKeys: String, CodingKey {
            case workspaceID
            case sidebarMode
            case tree
        }
    }
}
