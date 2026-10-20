import DevysClient
import Foundation
import Testing

@Suite("Coding outcome")
struct CodingOutcomeTests {
    @Test("Reads the latest check, changes, pull request and commit; nothing without a commit")
    func outcome() {
        #expect(CodingOutcome([CommitmentEvidence(author: "employee:e1", note: "Wrote it", recordedAt: "2026-10-20")]) == nil)
        let outcome = CodingOutcome([
            CommitmentEvidence(author: "employee:e1", note: "Committed", recordedAt: "a", commit: String(repeating: "a", count: 40), changes: "2 files changed"),
            CommitmentEvidence(author: "devys", note: "failed", recordedAt: "b", commit: String(repeating: "a", count: 40), check: .init(command: "bun test", exitCode: 1)),
            CommitmentEvidence(author: "devys", note: "passed", recordedAt: "c", commit: String(repeating: "b", count: 40), check: .init(command: "bun test", exitCode: 0)),
            CommitmentEvidence(author: "employee:e1", note: "Published", recordedAt: "d", commit: String(repeating: "b", count: 40), pullRequest: "https://github.com/acme/site/pull/12")
        ])
        #expect(outcome?.commit == "bbbbbbb")
        #expect(outcome?.changes == "2 files changed")
        #expect(outcome?.checkPassed == true)
        #expect(outcome?.pullRequestLabel == "PR #12")
    }
}
