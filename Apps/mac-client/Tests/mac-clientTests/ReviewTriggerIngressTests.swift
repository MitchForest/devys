import AppFeatures
import Foundation
import Testing
@testable import mac_client

@Suite("Review Trigger Ingress Tests")
struct ReviewTriggerIngressTests {
    @Test("Review trigger payloads map post-commit requests into structured review runs")
    func payloadMapping() throws {
        let payload = try ReviewTriggerIngress.makePayload(
            .init(
                workspaceID: "/tmp/devys/worktrees/feature-review",
                repositoryRootPath: "/tmp/devys/repo",
                triggerSource: "post-commit-hook",
                targetKind: "last-commit",
                commitSHA: "abcdef1234567890",
                branchName: "feature/review",
                title: nil
            )
        )

        #expect(payload.workspaceID == "/tmp/devys/worktrees/feature-review")
        #expect(payload.repositoryRootURL.path == "/tmp/devys/repo")
        #expect(payload.trigger.source == .postCommitHook)
        #expect(payload.target.kind == .lastCommit)
        #expect(payload.target.title == "Commit abcdef1")
        #expect(payload.target.branchName == "feature/review")
        #expect(payload.target.commitShas == ["abcdef1234567890"])
    }

    @Test("Review trigger payloads reject invalid target values")
    func invalidTargetRejected() {
        #expect(throws: (any Error).self) {
            try ReviewTriggerIngress.makePayload(
                .init(
                    workspaceID: nil,
                    repositoryRootPath: "/tmp/devys/repo",
                    triggerSource: "post-commit-hook",
                    targetKind: "pull-request-range",
                    commitSHA: nil,
                    branchName: nil,
                    title: nil
                )
            )
        }
    }
}
