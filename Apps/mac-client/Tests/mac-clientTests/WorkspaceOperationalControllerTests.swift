import AppFeatures
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Operational Controller Tests")
struct WorkspaceOperationalControllerTests {
    @Test("Controller publishes unread terminal snapshots and clears them on read")
    @MainActor
    func terminalUnreadSnapshots() async {
        let controller = WorkspaceOperationalController()
        let workspaceID = "/tmp/devys/worktrees/controller"

        var iterator = controller.updates().makeAsyncIterator()
        let initialSnapshot = await iterator.next()
        #expect(initialSnapshot?.unreadTerminalIDsByWorkspaceID.isEmpty == true)

        let session = controller.createTerminalSession(in: workspaceID)
        _ = await iterator.next()

        session.bellCount = 1
        var unreadSnapshot: WorkspaceOperationalSnapshot?
        for _ in 0..<5 {
            guard let snapshot = await iterator.next() else { break }
            if snapshot.unreadTerminalIDsByWorkspaceID[workspaceID] == Set([session.id]) {
                unreadSnapshot = snapshot
                break
            }
        }
        if unreadSnapshot == nil {
            Issue.record("Timed out waiting for unread workspace operational snapshot")
        }
        #expect(unreadSnapshot?.unreadTerminalIDsByWorkspaceID[workspaceID] == Set([session.id]))

        controller.markTerminalRead(session.id, in: workspaceID)
        var clearedSnapshot: WorkspaceOperationalSnapshot?
        for _ in 0..<5 {
            guard let snapshot = await iterator.next() else { break }
            if snapshot.unreadTerminalIDsByWorkspaceID[workspaceID] == nil {
                clearedSnapshot = snapshot
                break
            }
        }
        if clearedSnapshot == nil {
            Issue.record("Timed out waiting for cleared workspace operational snapshot")
        }
        #expect(clearedSnapshot?.unreadTerminalIDsByWorkspaceID[workspaceID] == nil)
    }
}
