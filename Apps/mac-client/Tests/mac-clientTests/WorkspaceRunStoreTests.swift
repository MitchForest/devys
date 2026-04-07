import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("WorkspaceRunStore Tests")
struct WorkspaceRunStoreTests {
    @Test("Setting a worktree running stores all launched resources")
    @MainActor
    func setRunning() {
        let store = WorkspaceRunStore()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-run"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-run")
        )
        let terminalId = UUID()
        let processId = UUID()
        let profileID = UUID()

        store.setRunning(
            worktreeId: worktree.id,
            profileID: profileID,
            terminalIDs: [terminalId],
            backgroundProcessIDs: [processId]
        )

        let state = store.state(for: worktree.id)
        #expect(state?.profileID == profileID)
        #expect(state?.terminalIDs == Set([terminalId]))
        #expect(state?.backgroundProcessIDs == Set([processId]))
        #expect(state?.isRunning == true)
    }

    @Test("Removing a terminal keeps other launched resources active")
    @MainActor
    func removeTerminal() {
        let store = WorkspaceRunStore()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-stop"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-stop")
        )
        let terminalId = UUID()
        let processId = UUID()

        store.setRunning(
            worktreeId: worktree.id,
            profileID: UUID(),
            terminalIDs: [terminalId],
            backgroundProcessIDs: [processId]
        )
        store.removeTerminal(terminalId)

        let state = store.state(for: worktree.id)
        #expect(state?.terminalIDs.isEmpty == true)
        #expect(state?.backgroundProcessIDs == Set([processId]))
        #expect(state?.isRunning == true)
    }

    @Test("Removing the last resource clears the worktree run state")
    @MainActor
    func removeLastResource() {
        let store = WorkspaceRunStore()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-a")
        )
        let terminalId = UUID()

        store.setRunning(
            worktreeId: worktree.id,
            profileID: UUID(),
            terminalIDs: [terminalId]
        )
        store.removeTerminal(terminalId)

        #expect(store.state(for: worktree.id) == nil)
    }
}
