import Foundation
import Testing
import Workspace
@testable import AppFeatures

@Suite("Workspace Operational State Tests")
struct WorkspaceOperationalStateTests {
    @Test("Unread terminal snapshots become reducer-owned attention notifications")
    func terminalSnapshotsCreateNotifications() {
        let workspaceID = "/tmp/devys/worktrees/attention"
        let terminalID = UUID(uuidString: "2C79DDA1-DC02-4D8A-A3B9-9AF6314EACAA")!
        let now = Date(timeIntervalSince1970: 100)
        var state = WorkspaceOperationalState()

        state.applySnapshot(
            WorkspaceOperationalSnapshot(
                unreadTerminalIDsByWorkspaceID: [workspaceID: Set([terminalID])]
            ),
            terminalNotificationsEnabled: true,
            now: now
        )

        let notifications = state.notifications(for: workspaceID)
        #expect(notifications.count == 1)
        #expect(notifications[0].source == .terminal)
        #expect(notifications[0].kind == .unread)
        #expect(notifications[0].terminalID == terminalID)
        #expect(state.attentionSummary(for: workspaceID).unreadCount == 1)
    }

    @Test("Attention preferences clear chat and terminal notifications by policy")
    func notificationPreferencesDriveVisibleAttention() {
        let workspaceID = "/tmp/devys/worktrees/preferences"
        let terminalID = UUID(uuidString: "987F25C1-1C5B-442E-8101-B1A8BA37E6AA")!
        let now = Date(timeIntervalSince1970: 100)
        var state = WorkspaceOperationalState()

        state.applySnapshot(
            WorkspaceOperationalSnapshot(
                unreadTerminalIDsByWorkspaceID: [workspaceID: Set([terminalID])]
            ),
            terminalNotificationsEnabled: true,
            now: now
        )
        state.ingest(
            WorkspaceAttentionIngressPayload(
                workspaceID: workspaceID,
                source: .claude,
                kind: .waiting,
                terminalID: nil,
                title: "Claude needs approval",
                subtitle: "permission prompt"
            ),
            chatNotificationsEnabled: true,
            terminalNotificationsEnabled: true,
            now: Date(timeIntervalSince1970: 200)
        )

        state.syncAttentionPreferences(
            terminalNotificationsEnabled: true,
            chatNotificationsEnabled: false,
            now: Date(timeIntervalSince1970: 300)
        )

        #expect(Set(state.notifications(for: workspaceID).map(\.source)) == [.terminal])

        state.syncAttentionPreferences(
            terminalNotificationsEnabled: false,
            chatNotificationsEnabled: false,
            now: Date(timeIntervalSince1970: 400)
        )

        #expect(state.notifications(for: workspaceID).isEmpty)
        #expect(state.latestUnreadNotification() == nil)
    }

    @Test("Run state clears when the last managed resource is removed")
    func runStateLifecycle() {
        let workspaceID = "/tmp/devys/worktrees/run"
        let terminalID = UUID(uuidString: "29EC3909-A08B-4FDD-BB53-51D02CA4527F")!
        let processID = UUID(uuidString: "38D36E07-0FD4-4830-96A3-6AE00D2ED0A9")!
        let profileID = UUID(uuidString: "5FE0A426-669F-4552-B7DB-3025EA67D557")!
        var state = WorkspaceOperationalState()

        state.setRunState(
            WorkspaceRunState(
                profileID: profileID,
                terminalIDs: Set([terminalID]),
                backgroundProcessIDs: Set([processID])
            ),
            for: workspaceID
        )
        #expect(state.runStatesByWorkspaceID[workspaceID]?.isRunning == true)

        state.removeRunTerminal(terminalID)
        #expect(state.runStatesByWorkspaceID[workspaceID]?.terminalIDs.isEmpty == true)
        #expect(state.runStatesByWorkspaceID[workspaceID]?.backgroundProcessIDs == Set([processID]))

        state.removeRunBackgroundProcess(processID)
        #expect(state.runStatesByWorkspaceID[workspaceID] == nil)
    }
}
