import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("RunCommandStore Tests")
struct RunCommandStoreTests {
    @Test("Setting a worktree running stores terminal state")
    @MainActor
    func setRunning() {
        let store = RunCommandStore()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-run"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-run")
        )
        let terminalId = UUID()

        store.setRunning(worktreeId: worktree.id, terminalId: terminalId)

        let state = store.state(for: worktree.id)
        #expect(state?.terminalId == terminalId)
        #expect(state?.isRunning == true)
    }

    @Test("Stopping preserves terminal identity and clears running flag")
    @MainActor
    func markStopped() {
        let store = RunCommandStore()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-stop"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-stop")
        )
        let terminalId = UUID()
        store.setRunning(worktreeId: worktree.id, terminalId: terminalId)

        store.markStopped(worktreeId: worktree.id)

        let state = store.state(for: worktree.id)
        #expect(state?.terminalId == terminalId)
        #expect(state?.isRunning == false)
    }

    @Test("Clearing a terminal removes all matching worktrees")
    @MainActor
    func clearTerminal() {
        let store = RunCommandStore()
        let terminalId = UUID()
        let first = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-a")
        )
        let second = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-b"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-b")
        )

        store.setRunning(worktreeId: first.id, terminalId: terminalId)
        store.setRunning(worktreeId: second.id, terminalId: UUID())

        store.clearTerminal(terminalId)

        #expect(store.state(for: first.id) == nil)
        #expect(store.state(for: second.id) != nil)
    }
}
