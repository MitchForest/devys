import AppFeatures
import Foundation
import Testing
@testable import mac_client

@Suite("Review Trigger Inbox Tests")
struct ReviewTriggerInboxStoreTests {
    @Test("Queued review triggers replay when observation starts")
    @MainActor
    func replaysQueuedTriggersOnStartup() async throws {
        let fixture = ReviewTriggerInboxFixture()
        defer { fixture.cleanup() }

        let store = ReviewTriggerInboxStore(inboxDirectoryURL: fixture.inboxDirectoryURL)
        let request = makeRequest(
            repositoryRootURL: fixture.repositoryRootURL,
            commitSHA: "abcdef1234567890",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try store.enqueue(request)

        let notificationCenter = NotificationCenter()
        let bridge = makeBridge(
            store: store,
            notificationCenter: notificationCenter
        )
        let received = await nextRequest(from: bridge.updates())

        #expect(received == request)
        #expect(try store.drain().isEmpty)
    }

    @Test("Wake signals drain review triggers queued after observation starts")
    @MainActor
    func drainsQueuedTriggersOnWakeSignal() async throws {
        let fixture = ReviewTriggerInboxFixture()
        defer { fixture.cleanup() }

        let store = ReviewTriggerInboxStore(inboxDirectoryURL: fixture.inboxDirectoryURL)
        let notificationCenter = NotificationCenter()
        let bridge = makeBridge(
            store: store,
            notificationCenter: notificationCenter
        )
        let stream = bridge.updates()

        let receiveTask = Task {
            await nextRequest(from: stream)
        }

        let request = makeRequest(
            repositoryRootURL: fixture.repositoryRootURL,
            commitSHA: "1234567890abcdef",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        try store.enqueue(request)
        notificationCenter.post(name: .devysReviewTriggerIngress, object: nil)

        let received = await receiveTask.value
        #expect(received == request)
        #expect(try store.drain().isEmpty)
    }
}

private struct ReviewTriggerInboxFixture {
    let inboxDirectoryURL: URL
    let repositoryRootURL: URL

    init() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-review-trigger-inbox-\(UUID().uuidString)")
        inboxDirectoryURL = rootURL.appendingPathComponent("inbox", isDirectory: true)
        repositoryRootURL = rootURL.appendingPathComponent("repo", isDirectory: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(
            at: inboxDirectoryURL.deletingLastPathComponent()
        )
    }
}

@MainActor
private func makeBridge(
    store: ReviewTriggerInboxStore,
    notificationCenter: NotificationCenter
) -> ReviewTriggerIngressBridge {
    ReviewTriggerIngressBridge(
        inboxStore: store,
        addWakeObserver: { handler in
            notificationCenter.addObserver(
                forName: .devysReviewTriggerIngress,
                object: nil,
                queue: .main
            ) { _ in
                handler()
            }
        },
        removeWakeObserver: { observer in
            notificationCenter.removeObserver(observer)
        }
    )
}

private func makeRequest(
    repositoryRootURL: URL,
    commitSHA: String,
    createdAt: Date
) -> ReviewTriggerRequest {
    ReviewTriggerRequest(
        workspaceID: "workspace-id",
        repositoryRootURL: repositoryRootURL,
        target: ReviewTarget(
            id: "workspace-id:lastCommit:\(commitSHA)",
            kind: .lastCommit,
            workspaceID: "workspace-id",
            repositoryRootURL: repositoryRootURL,
            title: "Commit \(String(commitSHA.prefix(7)))",
            branchName: "feature/review",
            commitShas: [commitSHA]
        ),
        trigger: ReviewTrigger(
            id: UUID(),
            source: .postCommitHook,
            createdAt: createdAt,
            isUserVisible: true
        )
    )
}

private func nextRequest(
    from stream: AsyncStream<ReviewTriggerRequest>
) async -> ReviewTriggerRequest? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}
