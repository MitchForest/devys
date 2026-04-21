import AppFeatures
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Review Audit Controller Tests")
struct ReviewAuditControllerTests {
    @Test("Review persistence store round-trips runs and issues")
    func reviewPersistenceStoreRoundTrip() async throws {
        let fixture = try TestReviewRepositoryFixture()
        defer { fixture.cleanup() }

        let store = ReviewPersistenceStore()
        let run = ReviewRun(
            id: UUID(),
            target: ReviewTarget(
                id: "staged",
                kind: .stagedChanges,
                workspaceID: fixture.workspaceID,
                repositoryRootURL: fixture.repositoryRoot,
                title: "Staged Changes"
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(),
            status: .completed,
            issueCounts: ReviewIssueCounts(total: 1, open: 1, major: 1),
            issueIDs: []
        )
        let issue = ReviewIssue(
            runID: run.id,
            severity: .major,
            confidence: .high,
            title: "Missing validation",
            summary: "Summary",
            rationale: "Rationale",
            paths: ["Sources/Feature.swift"],
            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 12)],
            dedupeKey: "feature#missing-validation"
        )

        try await store.saveRun(run, issues: [issue], rootURL: fixture.repositoryRoot)
        let snapshot = try await store.loadWorkspace(
            workspaceID: fixture.workspaceID,
            rootURL: fixture.repositoryRoot
        )

        #expect(snapshot.runs == [run])
        #expect(snapshot.issues == [issue])
    }

    @Test("Review persistence prunes old inactive runs but keeps active runs")
    func reviewPersistenceStorePrunesInactiveHistory() async throws {
        let fixture = try TestReviewRepositoryFixture()
        defer { fixture.cleanup() }

        let store = ReviewPersistenceStore()
        let activeRun = makeActiveReviewRun(fixture: fixture)
        try await store.saveRun(activeRun, issues: [], rootURL: fixture.repositoryRoot)

        let inactiveRunIDs = try await persistInactiveReviewRuns(
            count: 27,
            store: store,
            fixture: fixture
        )

        let snapshot = try await store.loadWorkspace(
            workspaceID: fixture.workspaceID,
            rootURL: fixture.repositoryRoot
        )

        assertPrunedReviewSnapshot(
            snapshot,
            activeRunID: activeRun.id,
            inactiveRunIDs: inactiveRunIDs,
            repositoryRoot: fixture.repositoryRoot
        )
    }

    @Test("Headless review audit executes and persists artifacts")
    func headlessReviewAuditExecutes() async throws {
        let fixture = try TestReviewRepositoryFixture()
        defer { fixture.cleanup() }

        let executableURL = try fixture.writeAuditExecutable(
            named: "fake-codex",
            output: """
            {
              "overallRisk": "medium",
              "issues": [
                {
                  "severity": "major",
                  "confidence": "high",
                  "title": "Review issue",
                  "summary": "The change needs a guard.",
                  "rationale": "Without the guard the feature can regress.",
                  "paths": ["notes.txt"],
                  "locations": [{"path": "notes.txt", "line": 1, "column": 1}],
                  "sourceReferences": ["AGENTS.md"],
                  "dedupeKey": "notes#review-issue"
                }
              ]
            }
            """
        )
        let settings = RepositorySettings(
            codexLauncher: LauncherTemplate(executable: executableURL.path),
            review: ReviewSettings(auditHarness: .codex)
        )
        let controller = ReviewAuditController { _ in settings }

        let result = try await controller.run(fixture.makeRequest())

        #expect(result.overallRisk == .medium)
        #expect(result.issues.count == 1)
        #expect(result.issues[0].runID == fixture.runID)
        #expect(result.issues[0].paths == ["notes.txt"])
        #expect(result.artifactSet.auditPromptPath != nil)
        #expect(result.artifactSet.inputSnapshotPath != nil)
        #expect(result.artifactSet.parsedResultPath != nil)
        #expect(result.artifactSet.rawStdoutPath != nil)

        let prompt = try String(
            contentsOfFile: try #require(result.artifactSet.auditPromptPath),
            encoding: .utf8
        )
        #expect(prompt.contains("Output JSON only."))
        #expect(prompt.contains("AGENTS.md"))

        let parsed = try String(
            contentsOfFile: try #require(result.artifactSet.parsedResultPath),
            encoding: .utf8
        )
        #expect(parsed.contains("\"overallRisk\" : \"medium\""))
    }

    @Test("Pull-request review targets diff HEAD against the PR base branch")
    func pullRequestReviewUsesBaseBranchContext() async throws {
        let fixture = try TestReviewRepositoryFixture()
        defer { fixture.cleanup() }
        try fixture.createFeatureChange(
            branchName: "feature/pr-review",
            fileName: "notes.txt",
            contents: "notes\nfeature branch change\n"
        )

        let executableURL = try fixture.writeAuditExecutable(
            named: "fake-codex-pr",
            output: """
            {
              "overallRisk": null,
              "issues": []
            }
            """
        )
        let settings = RepositorySettings(
            codexLauncher: LauncherTemplate(executable: executableURL.path),
            review: ReviewSettings(auditHarness: .codex)
        )
        let controller = ReviewAuditController { _ in settings }

        let request = fixture.makePullRequestRequest(
            branchName: "feature/pr-review",
            baseBranchName: "main",
            pullRequestNumber: 42,
            title: "#42 Review flow"
        )

        let result = try await controller.run(request)
        #expect(result.issues.isEmpty)

        let snapshot = try String(
            contentsOfFile: try #require(result.artifactSet.inputSnapshotPath),
            encoding: .utf8
        )
        #expect(snapshot.contains("Kind: Pull Request"))
        #expect(snapshot.contains("Base: Pull request #42 against main"))
        #expect(snapshot.contains("feature/pr-review"))
        #expect(snapshot.contains("feature branch change"))
    }

    @Test("Malformed audit output becomes a review execution failure with artifacts")
    func malformedAuditOutputFailsWithArtifacts() async throws {
        let fixture = try TestReviewRepositoryFixture()
        defer { fixture.cleanup() }

        let executableURL = try fixture.writeAuditExecutable(
            named: "fake-codex-bad",
            output: "not json"
        )
        let settings = RepositorySettings(
            codexLauncher: LauncherTemplate(executable: executableURL.path),
            review: ReviewSettings(auditHarness: .codex)
        )
        let controller = ReviewAuditController { _ in settings }

        do {
            _ = try await controller.run(fixture.makeRequest())
            Issue.record("Expected malformed audit output to fail.")
        } catch let failure as ReviewExecutionFailure {
            #expect(failure.message == "Review audit returned malformed JSON.")
            let stdoutPath = try #require(failure.artifactSet.rawStdoutPath)
            let stdout = try String(contentsOfFile: stdoutPath, encoding: .utf8)
            #expect(stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "not json")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private func assertPrunedReviewSnapshot(
    _ snapshot: ReviewWorkspaceSnapshot,
    activeRunID: UUID,
    inactiveRunIDs: [UUID],
    repositoryRoot: URL
) {
    #expect(snapshot.runs.count == 26)
    #expect(snapshot.runs.contains { $0.id == activeRunID })
    #expect(snapshot.runs.filter { $0.status.isActive }.map(\.id) == [activeRunID])
    #expect(snapshot.runs.filter { !$0.status.isActive }.count == 25)
    #expect(snapshot.runs.contains { $0.id == inactiveRunIDs[0] } == false)
    #expect(snapshot.runs.contains { $0.id == inactiveRunIDs[1] } == false)
    #expect(snapshot.runs.contains { $0.id == inactiveRunIDs[26] })

    let activeRunURL = ReviewStorageLocations.runDirectory(
        for: repositoryRoot,
        runID: activeRunID
    )
    let prunedRunURL = ReviewStorageLocations.runDirectory(
        for: repositoryRoot,
        runID: inactiveRunIDs[0]
    )
    #expect(FileManager.default.fileExists(atPath: activeRunURL.path))
    #expect(FileManager.default.fileExists(atPath: prunedRunURL.path) == false)
}

private func makeActiveReviewRun(
    fixture: TestReviewRepositoryFixture
) -> ReviewRun {
    ReviewRun(
        id: UUID(),
        target: ReviewTarget(
            id: "active",
            kind: .stagedChanges,
            workspaceID: fixture.workspaceID,
            repositoryRootURL: fixture.repositoryRoot,
            title: "Active Review"
        ),
        trigger: ReviewTrigger(source: .manual),
        profile: ReviewProfile(),
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1),
        startedAt: Date(timeIntervalSince1970: 1)
    )
}

private func persistInactiveReviewRuns(
    count: Int,
    store: ReviewPersistenceStore,
    fixture: TestReviewRepositoryFixture
) async throws -> [UUID] {
    var inactiveRunIDs: [UUID] = []
    for index in 0..<count {
        let date = Date(timeIntervalSince1970: TimeInterval(100 + index))
        let run = ReviewRun(
            id: UUID(),
            target: ReviewTarget(
                id: "inactive-\(index)",
                kind: .stagedChanges,
                workspaceID: fixture.workspaceID,
                repositoryRootURL: fixture.repositoryRoot,
                title: "Inactive Review \(index)"
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(),
            status: .completed,
            createdAt: date,
            startedAt: date,
            completedAt: date
        )
        inactiveRunIDs.append(run.id)
        try await store.saveRun(run, issues: [], rootURL: fixture.repositoryRoot)
    }
    return inactiveRunIDs
}

private struct TestReviewRepositoryFixture {
    let workspaceID: Workspace.ID = "workspace-review-tests"
    let repositoryRoot: URL
    let runID = UUID()

    init() throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        try """
        # Test Repo Instructions

        Keep code explicit.
        """.write(
            to: repositoryRoot.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "notes\n".write(
            to: repositoryRoot.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(arguments: ["init", "-b", "main"])
        try runGit(arguments: ["config", "user.name", "Devys Tests"])
        try runGit(arguments: ["config", "user.email", "tests@devys.local"])
        try runGit(arguments: ["add", "AGENTS.md", "notes.txt"])
        try runGit(arguments: ["commit", "-m", "Initial commit"])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func createFeatureChange(
        branchName: String,
        fileName: String,
        contents: String
    ) throws {
        try runGit(arguments: ["checkout", "-b", branchName])
        try contents.write(
            to: repositoryRoot.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
        try runGit(arguments: ["add", fileName])
        try runGit(arguments: ["commit", "-m", "Feature branch change"])
    }

    func makeRequest() -> ReviewExecutionRequest {
        ReviewExecutionRequest(
            runID: runID,
            workspaceID: workspaceID,
            workingDirectoryURL: repositoryRoot,
            target: ReviewTarget(
                id: "last-commit",
                kind: .lastCommit,
                workspaceID: workspaceID,
                repositoryRootURL: repositoryRoot,
                title: "Last Commit"
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(
                auditHarness: .codex,
                followUpHarness: .codex
            )
        )
    }

    func makePullRequestRequest(
        branchName: String,
        baseBranchName: String,
        pullRequestNumber: Int,
        title: String
    ) -> ReviewExecutionRequest {
        ReviewExecutionRequest(
            runID: runID,
            workspaceID: workspaceID,
            workingDirectoryURL: repositoryRoot,
            target: ReviewTarget(
                id: "pull-request-\(pullRequestNumber)",
                kind: .pullRequest,
                workspaceID: workspaceID,
                repositoryRootURL: repositoryRoot,
                title: title,
                branchName: branchName,
                baseBranchName: baseBranchName,
                pullRequestNumber: pullRequestNumber
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(
                auditHarness: .codex,
                followUpHarness: .codex
            )
        )
    }

    func writeAuditExecutable(
        named name: String,
        output: String
    ) throws -> URL {
        let executableURL = repositoryRoot.appendingPathComponent(name, isDirectory: false)
        let script = """
        #!/bin/zsh
        if [[ "$1" == "exec" ]]; then
          shift
        fi
        printf '%s\\n' \(shellQuoted(output))
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        return executableURL
    }

    func runGit(
        arguments: [String]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
