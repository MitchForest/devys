import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Attention Store Tests")
struct WorkspaceAttentionStoreTests {
    @Test("Terminal bell notifications are elevated to workspace unread state and clear on read")
    @MainActor
    func terminalBellAttention() {
        let registry = WorkspaceTerminalRegistry()
        let store = WorkspaceAttentionStore()
        let workspaceID = "/tmp/devys/worktrees/attention"
        let session = registry.createSession(in: workspaceID)

        session.bellCount = 1
        registry.syncUnreadState()
        store.syncFromTerminalRegistry(
            registry,
            now: Date(timeIntervalSince1970: 100)
        )

        let notifications = store.notifications(for: workspaceID)
        #expect(notifications.count == 1)
        #expect(notifications[0].source == .terminal)
        #expect(notifications[0].kind == .unread)
        #expect(store.summary(for: workspaceID).unreadCount == 1)

        store.markTerminalRead(session.id, in: workspaceID)

        #expect(store.notifications(for: workspaceID).isEmpty)
        #expect(store.summary(for: workspaceID).unreadCount == 0)
    }

    @Test("Waiting notifications are workspace-owned and completed clears waiting for the same terminal")
    @MainActor
    func waitingAndCompletedAttention() {
        let store = WorkspaceAttentionStore()
        let workspaceID = "/tmp/devys/worktrees/claude"
        let terminalID = UUID()

        store.recordWaiting(
            in: workspaceID,
            source: .claude,
            terminalID: terminalID,
            title: "Claude is waiting",
            now: Date(timeIntervalSince1970: 100)
        )

        let waitingSummary = store.summary(for: workspaceID)
        #expect(waitingSummary.waitingCount == 1)
        #expect(waitingSummary.latestWaitingSource == .claude)

        store.recordCompleted(
            in: workspaceID,
            source: .claude,
            terminalID: terminalID,
            title: "Claude completed",
            now: Date(timeIntervalSince1970: 200)
        )

        let notifications = store.notifications(for: workspaceID)
        #expect(notifications.count == 1)
        #expect(notifications[0].kind == .completed)
        #expect(notifications[0].source == .claude)

        let completedSummary = store.summary(for: workspaceID)
        #expect(completedSummary.waitingCount == 0)
        #expect(completedSummary.unreadCount == 1)
    }

    @Test("Clearing notifications by source preserves unrelated workspace attention")
    @MainActor
    func clearNotificationsBySource() {
        let store = WorkspaceAttentionStore()
        let workspaceID = "/tmp/devys/worktrees/mixed"

        store.recordWaiting(
            in: workspaceID,
            source: .claude,
            title: "Claude is waiting",
            now: Date(timeIntervalSince1970: 100)
        )
        store.recordCompleted(
            in: workspaceID,
            source: .run,
            title: "Run completed",
            now: Date(timeIntervalSince1970: 200)
        )
        store.ingest(
            WorkspaceAttentionIngressPayload(
                workspaceID: workspaceID,
                source: .terminal,
                kind: .unread,
                terminalID: UUID(),
                title: "Terminal needs attention",
                subtitle: nil
            ),
            now: Date(timeIntervalSince1970: 300)
        )

        store.clearNotifications(from: .terminal)

        let remainingSources = Set(store.notifications(for: workspaceID).map(\.source))
        #expect(remainingSources == [.claude, .run])

        store.clearNotifications(from: [.claude, .run])

        #expect(store.notifications(for: workspaceID).isEmpty)
    }
}
