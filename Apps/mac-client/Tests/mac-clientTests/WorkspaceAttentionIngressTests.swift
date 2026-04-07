import Foundation
import Testing
@testable import mac_client

@Suite("Workspace Attention Ingress Tests")
struct WorkspaceAttentionIngressTests {
    @Test("Hook payloads map Claude waiting notifications into workspace attention")
    func hookPayloadMapping() throws {
        let input = Data("""
        {
          "hook_event_name": "Notification",
          "message": "Claude needs your permission to use Bash",
          "title": "Permission needed",
          "notification_type": "permission_prompt"
        }
        """.utf8)

        let payload = try WorkspaceAttentionIngress.makePayload(
            fromHookInput: input,
            workspaceID: "/tmp/devys/worktrees/agent",
            terminalID: "2C79DDA1-DC02-4D8A-A3B9-9AF6314EACAA",
            source: "claude",
            kind: "waiting"
        )

        #expect(payload.workspaceID == "/tmp/devys/worktrees/agent")
        #expect(payload.source == .claude)
        #expect(payload.kind == .waiting)
        #expect(payload.title == "Permission needed")
        #expect(payload.subtitle == "permission prompt")
        #expect(payload.terminalID?.uuidString == "2C79DDA1-DC02-4D8A-A3B9-9AF6314EACAA")
    }

    @Test("Explicit payloads reject invalid source values")
    func invalidSourceRejected() {
        #expect(throws: (any Error).self) {
            try WorkspaceAttentionIngress.makePayload(
                workspaceID: "/tmp/devys/worktrees/agent",
                terminalID: nil,
                source: "gemini",
                kind: "waiting",
                title: "Unsupported",
                subtitle: nil
            )
        }
    }
}
