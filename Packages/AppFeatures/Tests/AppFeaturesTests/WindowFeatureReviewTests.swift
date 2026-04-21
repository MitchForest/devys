import AppFeatures
import ComposableArchitecture
import Foundation
import Git
import Split
import Testing
import Workspace

@Suite("WindowFeature Review Tests")
struct WindowFeatureReviewTests {
    @Test("Ingress-triggered reviews create a background run without opening a tab")
    @MainActor
    func startTriggeredReview() async {
        let reviewDate = Date(timeIntervalSince1970: 2_345_678)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/post-commit-review",
            detail: "feature/post-commit-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-post-commit-review"),
            repositoryRootURL: repository.rootURL
        )
        let runID = UUID(0)
        let issueID = UUID(200)
        let trigger = ReviewTrigger(
            id: UUID(99),
            source: .postCommitHook,
            createdAt: reviewDate,
            isUserVisible: true
        )
        let request = ReviewTriggerRequest(
            workspaceID: workspace.id,
            repositoryRootURL: repository.rootURL,
            target: ReviewTarget(
                id: "\(workspace.id):lastCommit:abcdef1",
                kind: .lastCommit,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                title: "Commit abcdef1",
                branchName: workspace.name,
                commitShas: ["abcdef1234567890"]
            ),
            trigger: trigger
        )
        let executionResult = ReviewExecutionResult(
            artifactSet: ReviewArtifactSet(rawStdoutPath: "reviews/\(runID.uuidString)/stdout.txt"),
            issues: [
                ReviewIssue(
                    id: issueID,
                    runID: UUID(999),
                    severity: .major,
                    confidence: .high,
                    title: "Post-commit regression",
                    summary: "The last commit removed a nil check.",
                    rationale: "The updated path now force unwraps state during launch.",
                    paths: ["Sources/Feature.swift"],
                    locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 18)],
                    dedupeKey: "post-commit-regression"
                )
            ]
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = reviewDate
            $0.repositorySettingsClient.load = { rootURL in
                #expect(rootURL == repository.rootURL)
                return RepositorySettings(
                    review: ReviewSettings(reviewOnCommit: true)
                )
            }
            $0.reviewExecutionClient.run = { executionRequest in
                #expect(executionRequest.runID == runID)
                #expect(executionRequest.workspaceID == workspace.id)
                #expect(executionRequest.target.kind == .lastCommit)
                #expect(executionRequest.trigger.source == .postCommitHook)
                return executionResult
            }
            $0.reviewPersistenceClient.saveRun = { run, issues, rootURL in
                #expect(run.id == runID)
                #expect(run.status == .completed)
                #expect(issues.map(\.id) == [issueID])
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(.reviewTriggerIngressReceived(request)) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: request.target,
                        trigger: trigger,
                        profile: ReviewProfile(),
                        status: .running,
                        createdAt: reviewDate,
                        startedAt: reviewDate
                    )
                ],
                issuesByRunID: [runID: []]
            )
        }

        await store.receive(
            .reviewExecutionFinished(
                workspaceID: workspace.id,
                runID: runID,
                result: .success(executionResult)
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: request.target,
                        trigger: trigger,
                        profile: ReviewProfile(),
                        status: .completed,
                        artifactSet: executionResult.artifactSet,
                        overallRisk: .medium,
                        issueCounts: ReviewIssueCounts(
                            total: 1,
                            open: 1,
                            major: 1
                        ),
                        issueIDs: [issueID],
                        createdAt: reviewDate,
                        startedAt: reviewDate,
                        completedAt: reviewDate
                    )
                ],
                issuesByRunID: [
                    runID: [
                        ReviewIssue(
                            id: issueID,
                            runID: runID,
                            severity: .major,
                            confidence: .high,
                            title: "Post-commit regression",
                            summary: "The last commit removed a nil check.",
                            rationale: "The updated path now force unwraps state during launch.",
                            paths: ["Sources/Feature.swift"],
                            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 18)],
                            dedupeKey: "post-commit-regression"
                        )
                    ]
                ]
            )
        }
    }

    @Test("Starting a manual review creates a run, opens the review tab, and stores results")
    @MainActor
    func startManualReview() async {
        let reviewDate = Date(timeIntervalSince1970: 1_234_567)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let paneID = PaneID(uuid: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let reviewTabID = TabID(uuid: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let runID = UUID(1)
        let issueID = UUID(200)
        let executionResult = ReviewExecutionResult(
            artifactSet: ReviewArtifactSet(auditPromptPath: "reviews/\(runID.uuidString)/audit.md"),
            issues: [
                ReviewIssue(
                    id: issueID,
                    runID: UUID(999),
                    severity: .critical,
                    confidence: .high,
                    title: "Missing bounds check",
                    summary: "Potential out-of-bounds read.",
                    rationale: "The new indexing path does not validate the array count.",
                    paths: ["Sources/Feature.swift"],
                    locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 42)],
                    dedupeKey: "missing-bounds-check"
                )
            ]
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id,
                workspaceShells: [
                    workspace.id: WindowFeature.WorkspaceShell(
                        tabContents: [
                            reviewTabID: .reviewRun(workspaceID: workspace.id, runID: runID)
                        ],
                        focusedPaneID: paneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .pane(
                                WindowFeature.WorkspacePaneLayout(
                                    id: paneID,
                                    tabIDs: [reviewTabID],
                                    selectedTabID: reviewTabID
                                )
                            )
                        )
                    )
                ],
                reviewEntryPresentation: WindowFeature.ReviewEntryPresentation(
                    workspaceID: workspace.id,
                    repositoryRootURL: repository.rootURL,
                    workspaceName: workspace.name,
                    branchName: workspace.name
                )
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = reviewDate
            $0.repositorySettingsClient.load = { rootURL in
                #expect(rootURL == repository.rootURL)
                return RepositorySettings()
            }
            $0.reviewExecutionClient.run = { request in
                #expect(request.runID == runID)
                #expect(request.workspaceID == workspace.id)
                #expect(request.target.kind == .stagedChanges)
                #expect(request.target.repositoryRootURL == repository.rootURL)
                #expect(request.profile.auditHarness == .codex)
                return executionResult
            }
            $0.reviewPersistenceClient.saveRun = { run, issues, rootURL in
                #expect(run.id == runID)
                #expect(run.status == .completed)
                #expect(issues.map(\.id) == [issueID])
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(
            WindowFeature.Action.startManualReview(
                workspaceID: workspace.id,
                targetKind: .stagedChanges
            )
        ) {
            $0.reviewEntryPresentation = nil
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: ReviewTarget(
                            id: "\(workspace.id):stagedChanges",
                            kind: .stagedChanges,
                            workspaceID: workspace.id,
                            repositoryRootURL: repository.rootURL,
                            title: "Staged Changes",
                            branchName: workspace.name
                        ),
                        trigger: ReviewTrigger(
                            id: UUID(0),
                            source: .manual,
                            createdAt: reviewDate,
                            isUserVisible: true
                        ),
                        profile: ReviewProfile(),
                        status: .running,
                        createdAt: reviewDate,
                        startedAt: reviewDate
                    )
                ],
                issuesByRunID: [runID: []]
            )
            $0.selectedTabID = reviewTabID
        }

        await store.receive(
            WindowFeature.Action.reviewExecutionFinished(
                workspaceID: workspace.id,
                runID: runID,
                result: .success(executionResult)
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: ReviewTarget(
                            id: "\(workspace.id):stagedChanges",
                            kind: .stagedChanges,
                            workspaceID: workspace.id,
                            repositoryRootURL: repository.rootURL,
                            title: "Staged Changes",
                            branchName: workspace.name
                        ),
                        trigger: ReviewTrigger(
                            id: UUID(0),
                            source: .manual,
                            createdAt: reviewDate,
                            isUserVisible: true
                        ),
                        profile: ReviewProfile(),
                        status: .completed,
                        artifactSet: executionResult.artifactSet,
                        overallRisk: .high,
                        issueCounts: ReviewIssueCounts(
                            total: 1,
                            open: 1,
                            critical: 1
                        ),
                        issueIDs: [issueID],
                        createdAt: reviewDate,
                        startedAt: reviewDate,
                        completedAt: reviewDate
                    )
                ],
                issuesByRunID: [
                    runID: [
                        ReviewIssue(
                            id: issueID,
                            runID: runID,
                            severity: .critical,
                            confidence: .high,
                            title: "Missing bounds check",
                            summary: "Potential out-of-bounds read.",
                            rationale: "The new indexing path does not validate the array count.",
                            paths: ["Sources/Feature.swift"],
                            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 42)],
                            dedupeKey: "missing-bounds-check"
                        )
                    ]
                ]
            )
        }
    }

    @Test("Starting a pull-request review uses the mapped PR base branch")
    @MainActor
    func startPullRequestReview() async {
        let reviewDate = Date(timeIntervalSince1970: 1_234_890)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let paneID = PaneID(uuid: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let reviewTabID = TabID(uuid: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let runID = UUID(1)
        let pullRequest = PullRequest(
            id: 42,
            number: 42,
            title: "Harden login review flow",
            body: nil,
            state: .open,
            author: "devys",
            headBranch: workspace.name,
            baseBranch: "main",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            isDraft: false,
            checksStatus: .passing,
            reviewDecision: .reviewRequired,
            additions: 10,
            deletions: 2,
            changedFiles: 3
        )
        let executionResult = ReviewExecutionResult()

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id,
                workspaceShells: [
                    workspace.id: WindowFeature.WorkspaceShell(
                        tabContents: [
                            reviewTabID: .reviewRun(workspaceID: workspace.id, runID: runID)
                        ],
                        focusedPaneID: paneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .pane(
                                WindowFeature.WorkspacePaneLayout(
                                    id: paneID,
                                    tabIDs: [reviewTabID],
                                    selectedTabID: reviewTabID
                                )
                            )
                        )
                    )
                ],
                reviewEntryPresentation: WindowFeature.ReviewEntryPresentation(
                    workspaceID: workspace.id,
                    repositoryRootURL: repository.rootURL,
                    workspaceName: workspace.name,
                    branchName: workspace.name,
                    pullRequestNumber: pullRequest.number,
                    pullRequestTitle: pullRequest.title,
                    availableTargets: ReviewTargetKind.manualEntryTargets + [.pullRequest]
                ),
                operational: {
                    var operational = WorkspaceOperationalState()
                    operational.metadataEntriesByWorkspaceID[workspace.id] = WorktreeInfoEntry(
                        branchName: workspace.name,
                        pullRequest: pullRequest
                    )
                    return operational
                }()
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = reviewDate
            $0.repositorySettingsClient.load = { rootURL in
                #expect(rootURL == repository.rootURL)
                return RepositorySettings()
            }
            $0.reviewExecutionClient.run = { request in
                #expect(request.runID == runID)
                #expect(request.workspaceID == workspace.id)
                #expect(request.target.kind == .pullRequest)
                #expect(request.target.pullRequestNumber == 42)
                #expect(request.target.branchName == workspace.name)
                #expect(request.target.baseBranchName == "main")
                #expect(request.target.title == "#42 Harden login review flow")
                return executionResult
            }
            $0.reviewPersistenceClient.deleteRun = { deletedRunID, rootURL in
                #expect(deletedRunID == runID)
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(
            WindowFeature.Action.startManualReview(
                workspaceID: workspace.id,
                targetKind: .pullRequest
            )
        ) {
            $0.reviewEntryPresentation = nil
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: ReviewTarget(
                            id: "\(workspace.id):pullRequest:42",
                            kind: .pullRequest,
                            workspaceID: workspace.id,
                            repositoryRootURL: repository.rootURL,
                            title: "#42 Harden login review flow",
                            branchName: workspace.name,
                            baseBranchName: "main",
                            pullRequestNumber: 42
                        ),
                        trigger: ReviewTrigger(
                            id: UUID(0),
                            source: .manual,
                            createdAt: reviewDate,
                            isUserVisible: true
                        ),
                        profile: ReviewProfile(),
                        status: .running,
                        createdAt: reviewDate,
                        startedAt: reviewDate
                    )
                ],
                issuesByRunID: [runID: []]
            )
            $0.selectedTabID = reviewTabID
        }

        await store.receive(
            WindowFeature.Action.reviewExecutionFinished(
                workspaceID: workspace.id,
                runID: runID,
                result: .success(executionResult)
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: ReviewTarget(
                            id: "\(workspace.id):pullRequest:42",
                            kind: .pullRequest,
                            workspaceID: workspace.id,
                            repositoryRootURL: repository.rootURL,
                            title: "#42 Harden login review flow",
                            branchName: workspace.name,
                            baseBranchName: "main",
                            pullRequestNumber: 42
                        ),
                        trigger: ReviewTrigger(
                            id: UUID(0),
                            source: .manual,
                            createdAt: reviewDate,
                            isUserVisible: true
                        ),
                        profile: ReviewProfile(),
                        status: .completed,
                        overallRisk: nil,
                        issueCounts: ReviewIssueCounts(),
                        issueIDs: [],
                        createdAt: reviewDate,
                        startedAt: reviewDate,
                        completedAt: reviewDate
                    )
                ],
                issuesByRunID: [
                    runID: []
                ]
            )
        }
    }

    @Test("Dismissing the final review issue updates reducer state and deletes persisted review history")
    @MainActor
    func dismissReviewIssue() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let runID = UUID(100)
        let issueID = UUID(101)
        let run = ReviewRun(
            id: runID,
            target: ReviewTarget(
                id: "\(workspace.id):stagedChanges",
                kind: .stagedChanges,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                title: "Staged Changes",
                branchName: workspace.name
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(),
            status: .completed,
            overallRisk: .high,
            issueCounts: ReviewIssueCounts(total: 1, open: 1, critical: 1),
            issueIDs: [issueID]
        )
        let issue = ReviewIssue(
            id: issueID,
            runID: runID,
            severity: .critical,
            confidence: .high,
            title: "Missing bounds check",
            summary: "Potential out-of-bounds read.",
            rationale: "The new indexing path does not validate the array count.",
            paths: ["Sources/Feature.swift"],
            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 42)],
            dedupeKey: "missing-bounds-check"
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                reviewWorkspacesByID: [
                    workspace.id: WindowFeature.ReviewWorkspaceState(
                        runs: [run],
                        issuesByRunID: [runID: [issue]]
                    )
                ],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.reviewPersistenceClient.deleteRun = { deletedRunID, rootURL in
                #expect(deletedRunID == runID)
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(
            WindowFeature.Action.dismissReviewIssue(
                workspaceID: workspace.id,
                runID: runID,
                issueID: issueID
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: run.target,
                        trigger: run.trigger,
                        profile: run.profile,
                        status: .completed,
                        artifactSet: run.artifactSet,
                        overallRisk: nil,
                        issueCounts: ReviewIssueCounts(
                            total: 1,
                            dismissed: 1,
                            critical: 1
                        ),
                        issueIDs: [issueID],
                        createdAt: run.createdAt,
                        startedAt: run.startedAt,
                        completedAt: run.completedAt,
                        lastErrorMessage: run.lastErrorMessage
                    )
                ],
                issuesByRunID: [
                    runID: [
                        ReviewIssue(
                            id: issueID,
                            runID: runID,
                            severity: .critical,
                            confidence: .high,
                            title: "Missing bounds check",
                            summary: "Potential out-of-bounds read.",
                            rationale: "The new indexing path does not validate the array count.",
                            paths: ["Sources/Feature.swift"],
                            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 42)],
                            dedupeKey: "missing-bounds-check",
                            status: .dismissed
                        )
                    ]
                ]
            )
        }
    }

    @Test("Deleting a review run removes it from reducer state and persistence")
    @MainActor
    func deleteReviewRun() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let runID = UUID(150)
        let issueID = UUID(151)
        let run = ReviewRun(
            id: runID,
            target: ReviewTarget(
                id: "\(workspace.id):stagedChanges",
                kind: .stagedChanges,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                title: "Staged Changes",
                branchName: workspace.name
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(),
            status: .failed,
            issueCounts: ReviewIssueCounts(total: 1, open: 1, critical: 1),
            issueIDs: [issueID]
        )
        let issue = ReviewIssue(
            id: issueID,
            runID: runID,
            severity: .critical,
            confidence: .high,
            title: "Missing bounds check",
            summary: "Potential out-of-bounds read.",
            rationale: "The new indexing path does not validate the array count.",
            paths: ["Sources/Feature.swift"],
            dedupeKey: "missing-bounds-check"
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                reviewWorkspacesByID: [
                    workspace.id: WindowFeature.ReviewWorkspaceState(
                        runs: [run],
                        issuesByRunID: [runID: [issue]]
                    )
                ],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.reviewPersistenceClient.deleteRun = { deletedRunID, rootURL in
                #expect(deletedRunID == runID)
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(
            .deleteReviewRun(
                workspaceID: workspace.id,
                runID: runID
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState()
        }
    }

    @Test("Investigating a review issue creates a staged launcher request and removes it from persisted attention state")
    @MainActor
    func investigateReviewIssue() async throws {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let runID = UUID(200)
        let issueID = UUID(201)
        let run = ReviewRun(
            id: runID,
            target: ReviewTarget(
                id: "\(workspace.id):stagedChanges",
                kind: .stagedChanges,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                title: "Staged Changes",
                branchName: workspace.name
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(),
            status: .completed,
            overallRisk: .high,
            issueCounts: ReviewIssueCounts(total: 1, open: 1, critical: 1),
            issueIDs: [issueID]
        )
        let issue = ReviewIssue(
            id: issueID,
            runID: runID,
            severity: .critical,
            confidence: .high,
            title: "Missing bounds check",
            summary: "Potential out-of-bounds read.",
            rationale: "The new indexing path does not validate the array count.",
            paths: ["Sources/Feature.swift"],
            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 42)],
            dedupeKey: "missing-bounds-check"
        )
        let draft = ReviewFixDraft(
            issueID: issueID,
            harness: .claude,
            resolvedCommandPreview: "claude \"$(cat prompt.md)\"",
            promptArtifactPath: "/tmp/reviews/\(issueID.uuidString).md"
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                reviewWorkspacesByID: [
                    workspace.id: WindowFeature.ReviewWorkspaceState(
                        runs: [run],
                        issuesByRunID: [runID: [issue]]
                    )
                ],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.repositorySettingsClient.load = { rootURL in
                #expect(rootURL == repository.rootURL)
                return RepositorySettings(
                    review: ReviewSettings(
                        followUpModelOverride: "sonnet",
                        followUpReasoningOverride: "high",
                        additionalInstructions: "Prefer the smallest safe fix."
                    )
                )
            }
            $0.reviewPersistenceClient.deleteRun = { deletedRunID, rootURL in
                #expect(deletedRunID == runID)
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(
            WindowFeature.Action.investigateReviewIssue(
                workspaceID: workspace.id,
                runID: runID,
                issueID: issueID,
                harness: BuiltInLauncherKind.claude
            )
        ) {
            $0.reviewIssueInvestigationRequest = WindowFeature.ReviewIssueInvestigationRequest(
                id: UUID(0),
                workspaceID: workspace.id,
                runID: runID,
                issueID: issueID,
                repositoryRootURL: repository.rootURL,
                workingDirectoryURL: workspace.workingDirectory,
                harness: .claude,
                launcher: LauncherTemplate(
                    executable: "claude",
                    model: "sonnet",
                    reasoningLevel: "high",
                    dangerousPermissions: true,
                    executionBehavior: .stageInTerminal
                ),
                prompt: """
                # Review Fix

                You are fixing a structured review finding for the Devys workspace `feature/login-review`.

                Context
                - Review target: Staged Changes
                - Original trigger: manual
                - Audit harness: codex
                - Review run ID: \(runID.uuidString)
                - Review issue ID: \(issueID.uuidString)

                Finding
                - Severity: critical
                - Confidence: high
                - Title: Missing bounds check
                - Summary: Potential out-of-bounds read.
                - Rationale: The new indexing path does not validate the array count.
                - Paths: Sources/Feature.swift
                - Locations: Sources/Feature.swift:42

                Instructions
                1. Confirm whether this finding is real.
                2. If it is real, implement the smallest correct fix now.
                3. If it is a false positive or should be deferred, explain why and do not make unrelated changes.
                4. Keep the patch focused on this finding and preserve explicit ownership boundaries.
                5. Summarize what changed and what you verified before you finish.

                Response format
                - Verdict: fixed | false-positive | defer
                - Changes: concise list or `none`
                - Validation: what you checked
                - Notes: anything still risky or deferred

                Repository-specific review instructions
                Prefer the smallest safe fix.
                """
            )
        }

        let request = try #require(store.state.reviewIssueInvestigationRequest)
        #expect(request.workspaceID == workspace.id)
        #expect(request.runID == runID)
        #expect(request.issueID == issueID)
        #expect(request.harness == BuiltInLauncherKind.claude)
        #expect(request.launcher.executionBehavior == LauncherExecutionBehavior.stageInTerminal)
        #expect(request.launcher.model == "sonnet")
        #expect(request.launcher.reasoningLevel == "high")
        #expect(request.prompt.contains("Missing bounds check"))
        #expect(request.prompt.contains("Sources/Feature.swift:42"))
        #expect(request.prompt.contains("Prefer the smallest safe fix."))
        #expect(request.prompt.contains("Verdict: fixed | false-positive | defer"))

        await store.send(
            WindowFeature.Action.reviewIssueInvestigationPrepared(
                workspaceID: workspace.id,
                runID: runID,
                draft: draft
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: run.target,
                        trigger: run.trigger,
                        profile: run.profile,
                        status: .completed,
                        artifactSet: run.artifactSet,
                        overallRisk: nil,
                        issueCounts: ReviewIssueCounts(
                            total: 1,
                            critical: 1
                        ),
                        issueIDs: [issueID],
                        createdAt: run.createdAt,
                        startedAt: run.startedAt,
                        completedAt: run.completedAt,
                        lastErrorMessage: run.lastErrorMessage
                    )
                ],
                issuesByRunID: [
                    runID: [
                        ReviewIssue(
                            id: issueID,
                            runID: runID,
                            severity: .critical,
                            confidence: .high,
                            title: "Missing bounds check",
                            summary: "Potential out-of-bounds read.",
                            rationale: "The new indexing path does not validate the array count.",
                            paths: ["Sources/Feature.swift"],
                            locations: [ReviewIssueLocation(path: "Sources/Feature.swift", line: 42)],
                            dedupeKey: "missing-bounds-check",
                            status: .followUpPrepared,
                            followUpPromptArtifactPath: draft.promptArtifactPath
                        )
                    ]
                ]
            )
        }
    }

    @Test("Changing the review fix harness updates the run profile and persists it")
    @MainActor
    func setReviewRunFollowUpHarness() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let runID = UUID(300)
        let issueID = UUID(301)
        let run = ReviewRun(
            id: runID,
            target: ReviewTarget(
                id: "\(workspace.id):stagedChanges",
                kind: .stagedChanges,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                title: "Staged Changes",
                branchName: workspace.name
            ),
            trigger: ReviewTrigger(source: .manual),
            profile: ReviewProfile(followUpHarness: .codex),
            status: .completed,
            overallRisk: .majorRiskFallback,
            issueCounts: ReviewIssueCounts(total: 1, open: 1, major: 1),
            issueIDs: [issueID]
        )
        let issue = ReviewIssue(
            id: issueID,
            runID: runID,
            severity: .major,
            confidence: .high,
            title: "Race condition",
            summary: "State can update from two async paths.",
            rationale: "The reducer and host mutation overlap.",
            paths: ["Sources/Feature.swift"],
            dedupeKey: "race-condition"
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                reviewWorkspacesByID: [
                    workspace.id: WindowFeature.ReviewWorkspaceState(
                        runs: [run],
                        issuesByRunID: [runID: [issue]]
                    )
                ],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.reviewPersistenceClient.saveRun = { persistedRun, issues, rootURL in
                #expect(persistedRun.id == runID)
                #expect(persistedRun.profile.followUpHarness == .claude)
                #expect(issues.map(\.id) == [issueID])
                #expect(rootURL == repository.rootURL)
            }
        }

        await store.send(
            .setReviewRunFollowUpHarness(
                workspaceID: workspace.id,
                runID: runID,
                harness: .claude
            )
        ) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                runs: [
                    ReviewRun(
                        id: runID,
                        target: run.target,
                        trigger: run.trigger,
                        profile: ReviewProfile(followUpHarness: .claude),
                        status: .completed,
                        artifactSet: run.artifactSet,
                        overallRisk: .majorRiskFallback,
                        issueCounts: run.issueCounts,
                        issueIDs: [issueID],
                        createdAt: run.createdAt,
                        startedAt: run.startedAt,
                        completedAt: run.completedAt,
                        lastErrorMessage: run.lastErrorMessage
                    )
                ],
                issuesByRunID: [runID: [issue]]
            )
        }
    }
}

private extension ReviewOverallRisk {
    static let majorRiskFallback: Self = .medium
}
