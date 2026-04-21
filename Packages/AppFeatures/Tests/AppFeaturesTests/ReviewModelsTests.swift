import Foundation
import Testing
@testable import AppFeatures
import Workspace

@Suite("Review Models Tests")
struct ReviewModelsTests {
    @Test("Review target falls back to canonical titles")
    func reviewTargetDisplayTitle() {
        let target = ReviewTarget(
            id: "staged",
            kind: .stagedChanges,
            workspaceID: "/tmp/devys/worktrees/main",
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys"),
            title: " "
        )

        #expect(target.displayTitle == "Staged Changes")
    }

    @Test("Review profile inherits review settings defaults")
    func reviewProfileFromSettings() {
        let settings = ReviewSettings(
            reviewOnCommit: true,
            auditHarness: .claude,
            followUpHarness: .codex,
            auditModelOverride: "sonnet",
            additionalInstructions: "Prefer explicit ownership."
        )

        let profile = ReviewProfile(settings: settings)

        #expect(profile.auditHarness == .claude)
        #expect(profile.followUpHarness == .codex)
        #expect(profile.auditModelOverride == "sonnet")
        #expect(profile.additionalInstructions == "Prefer explicit ownership.")
        #expect(profile.runnerLocation == .localHost)
    }

    @Test("Review workspace state resolves runs and issues by run id")
    func reviewWorkspaceStateStoresIssuesPerRun() {
        let workspaceID: Workspace.ID = "/tmp/devys/worktrees/main"
        let runID = UUID(100)
        let target = ReviewTarget(
            id: "staged",
            kind: .stagedChanges,
            workspaceID: workspaceID,
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys"),
            title: "Staged Changes"
        )
        let run = ReviewRun(
            id: runID,
            target: target,
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile()
        )
        let issue = ReviewIssue(
            id: UUID(101),
            runID: runID,
            severity: .major,
            confidence: .high,
            title: "Important issue",
            summary: "Important",
            rationale: "Important rationale",
            dedupeKey: "major"
        )

        let state = WindowFeature.State(
            reviewWorkspacesByID: [
                workspaceID: WindowFeature.ReviewWorkspaceState(
                    runs: [run],
                    issuesByRunID: [runID: [issue]]
                )
            ]
        )

        #expect(state.reviewRun(workspaceID: workspaceID, runID: runID)?.id == runID)
        #expect(state.reviewIssues(workspaceID: workspaceID, runID: runID).map(\.id) == [UUID(101)])
    }
}
