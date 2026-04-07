import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Port Managed Process Catalog Tests")
struct WorkspacePortManagedProcessCatalogTests {
    @Test("Hosted terminal sessions contribute direct workspace ownership")
    @MainActor
    func hostedSessionsContributeManagedOwnership() {
        let backgroundProcess = ManagedWorkspaceProcess(processID: 101, displayName: "Web")
        let hostedSession = HostedTerminalSessionRecord(
            id: UUID(),
            workspaceID: "/tmp/devys/repo-a",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            launchCommand: "pnpm dev",
            processID: 202,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let managedProcesses = WorkspacePortManagedProcessCatalog.makeManagedProcesses(
            backgroundProcessesByWorkspace: ["/tmp/devys/repo-a": [backgroundProcess]],
            hostedSessionsByID: [hostedSession.id: hostedSession]
        )

        #expect(managedProcesses["/tmp/devys/repo-a"]?.map(\.processID) == [101, 202])
        #expect(managedProcesses["/tmp/devys/repo-a"]?.map(\.displayName) == ["Web", "pnpm dev"])
    }

    @Test("Hosted sessions without a pid are ignored and duplicate pids are deduplicated")
    @MainActor
    func hostedSessionPidRulesAreApplied() {
        let backgroundProcess = ManagedWorkspaceProcess(processID: 101, displayName: "Web")
        let duplicateHostedSession = HostedTerminalSessionRecord(
            id: UUID(),
            workspaceID: "/tmp/devys/repo-a",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            launchCommand: "pnpm dev",
            processID: 101,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let pidlessHostedSession = HostedTerminalSessionRecord(
            id: UUID(),
            workspaceID: "/tmp/devys/repo-b",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-b"),
            launchCommand: "npm test",
            processID: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let managedProcesses = WorkspacePortManagedProcessCatalog.makeManagedProcesses(
            backgroundProcessesByWorkspace: ["/tmp/devys/repo-a": [backgroundProcess]],
            hostedSessionsByID: [
                duplicateHostedSession.id: duplicateHostedSession,
                pidlessHostedSession.id: pidlessHostedSession
            ]
        )

        #expect(managedProcesses["/tmp/devys/repo-a"]?.map(\.processID) == [101])
        #expect(managedProcesses["/tmp/devys/repo-a"]?.map(\.displayName) == ["pnpm dev"])
        #expect(managedProcesses["/tmp/devys/repo-b"] == nil)
    }
}
