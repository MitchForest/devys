import Testing
@testable import ChatCore

@Test func sessionCreation() {
    let session = Session(
        title: "Test",
        harnessType: .codex,
        model: "gpt-5-codex"
    )
    #expect(session.title == "Test")
    #expect(session.harnessType == .codex)
    #expect(session.status == .idle)
}

@Test func messageCreation() {
    let message = Message(
        sessionID: "test-session",
        role: .user,
        text: "Hello"
    )
    #expect(message.role == .user)
    #expect(message.streamingState == .idle)
    #expect(message.blocks.isEmpty)
}
