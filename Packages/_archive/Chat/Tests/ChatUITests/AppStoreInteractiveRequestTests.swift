import ChatCore
import Testing
@testable import ChatUI

@MainActor
@Test func appStoreSyncPendingInteractiveRequestsUsesLatestRequests() {
    let store = AppStore()

    let messages = [
        makeMessage(
            sessionID: "other",
            blocks: [approvalBlock(id: "approval-other", summary: "ignore")]
        ),
        makeMessage(
            sessionID: "session-1",
            blocks: [approvalBlock(id: "approval-1", summary: "first approval")]
        ),
        makeMessage(
            sessionID: "session-1",
            blocks: [inputBlock(id: "input-1", prompt: "first input")]
        ),
        makeMessage(
            sessionID: "session-1",
            blocks: [
                approvalBlock(id: "approval-2", summary: "latest approval"),
                inputBlock(id: "input-2", prompt: "latest input"),
            ]
        ),
    ]

    store.syncPendingInteractiveRequests(from: messages, sessionID: "session-1")

    #expect(store.pendingApprovalRequest?.requestID == "approval-2")
    #expect(store.pendingApprovalRequest?.prompt == "latest approval")
    #expect(store.pendingInputRequest?.requestID == "input-2")
    #expect(store.pendingInputRequest?.prompt == "latest input")
}

@MainActor
@Test func appStoreResetPendingInteractiveStateClearsPendingValues() {
    let store = AppStore()

    store.pendingApprovalRequest = AppStore.PendingApprovalRequest(
        sessionID: "session-1",
        requestID: "approval-1",
        prompt: "approve"
    )
    store.pendingInputRequest = AppStore.PendingInputRequest(
        sessionID: "session-1",
        requestID: "input-1",
        prompt: "input"
    )
    store.approvalNote = "notes"
    store.inputResponseText = "value"

    store.resetPendingInteractiveState()

    #expect(store.pendingApprovalRequest == nil)
    #expect(store.pendingInputRequest == nil)
    #expect(store.approvalNote.isEmpty)
    #expect(store.inputResponseText.isEmpty)
}

private func makeMessage(sessionID: String, blocks: [MessageBlock]) -> Message {
    Message(
        sessionID: sessionID,
        role: .assistant,
        text: "",
        blocks: blocks,
        streamingState: .complete
    )
}

private func approvalBlock(id: String, summary: String) -> MessageBlock {
    MessageBlock(
        id: id,
        kind: .toolCall,
        summary: summary,
        payload: .object([
            "approvalRequestId": .string(id),
        ])
    )
}

private func inputBlock(id: String, prompt: String) -> MessageBlock {
    MessageBlock(
        id: id,
        kind: .userInputRequest,
        summary: nil,
        payload: .object([
            "requestId": .string(id),
            "prompt": .string(prompt),
        ])
    )
}
