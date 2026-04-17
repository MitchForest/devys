import AppFeatures
import ComposableArchitecture
import Foundation
import Testing
import Workspace

@Suite("WindowFeature Workflow Tests")
struct WindowFeatureWorkflowTests {
    @Test("Starting a workflow run loads the plan and launches the entry node")
    @MainActor
    func startWorkflowRun() async throws {
        let repository = workflowTestRepository()
        let worktree = workflowTestWorktree(repository: repository)
        var definition = WorkflowDefinition.defaultDeliveryDefinition(
            id: "delivery",
            now: Date(timeIntervalSince1970: 100)
        )
        definition.planFilePath = "plan.md"
        let implementNode = try #require(definition.node(id: "implement"))
        let implementer = try #require(definition.worker(id: "implementer"))
        let runID = UUID(100)
        let terminalID = UUID(101)
        let recorder = WorkflowLaunchRecorder()
        let snapshot = workflowTestPlanSnapshot(worktreePath: worktree.workingDirectory.path)
        let expectedPrompt = WorkflowPromptRenderer.renderPrompt(
            definition: definition,
            node: implementNode,
            worker: implementer,
            snapshot: snapshot
        )
        let expectedPromptPreview = workflowTestPromptPreview(expectedPrompt)

        let store = TestStore(
            initialState: workflowTestState(
                repository: repository,
                worktree: worktree,
                definitions: [definition]
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 100)
            $0.uuid = .incrementing
            $0.workflowPersistenceClient.loadPlanSnapshot = { _, _ in snapshot }
            $0.workflowExecutionClient.startNode = { request in
                await recorder.record(request.node.id)
                return WorkflowNodeLaunchResult(
                    terminalID: terminalID,
                    launchedCommand: request.prompt,
                    promptArtifactPath: "/tmp/prompt.md"
                )
            }
        }

        await store.send(
            .startWorkflowRun(
                workspaceID: worktree.id,
                definitionID: definition.id,
                runID: runID
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs = [
                WorkflowRun(
                    id: runID,
                    definitionID: definition.id,
                    workspaceID: worktree.id,
                    worktreePath: worktree.workingDirectory.path,
                    branchName: worktree.name,
                    status: .idle,
                    currentNodeID: "implement",
                    attempts: [],
                    events: [
                        WorkflowRunEvent(
                            id: UUID(0),
                            timestamp: Date(timeIntervalSince1970: 100),
                            message: "Workflow run created."
                        )
                    ],
                    startedAt: Date(timeIntervalSince1970: 100),
                    updatedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        }

        await store.receive(
            .workflowPlanSnapshotLoaded(
                workspaceID: worktree.id,
                runID: runID,
                snapshot: snapshot
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].latestPlanSnapshot = snapshot
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(1),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Loaded bound plan snapshot."
                )
            )
        }

        await store.receive(.continueWorkflowRun(workspaceID: worktree.id, runID: runID)) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].status = .running
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].activeAttemptID = UUID(2)
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts = [
                WorkflowRunAttempt(
                    id: UUID(2),
                    nodeID: "implement",
                    workerID: "implementer",
                    status: .running,
                    terminalID: nil,
                    promptArtifactPath: nil,
                    promptPreview: expectedPromptPreview,
                    launchedCommand: nil,
                    startedAt: Date(timeIntervalSince1970: 100),
                    endedAt: nil
                )
            ]
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(3),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Launching Implement with Implementer."
                )
            )
        }

        await store.receive(
            .workflowNodeLaunchSucceeded(
                workspaceID: worktree.id,
                runID: runID,
                result: WorkflowNodeLaunchResult(
                    terminalID: terminalID,
                    launchedCommand: expectedPrompt,
                    promptArtifactPath: "/tmp/prompt.md"
                )
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].currentTerminalID = terminalID
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[0].terminalID = terminalID
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[0].promptArtifactPath =
                "/tmp/prompt.md"
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[0].launchedCommand =
                expectedPrompt
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(4),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Implement attached to terminal \(terminalID.uuidString)."
                )
            )
        }

        #expect(await recorder.nodeIDs == ["implement"])
    }

    @Test("Starting a workflow run is rejected when the workspace already has an active run")
    @MainActor
    func startWorkflowRunRejectsSecondActiveRun() async {
        let repository = workflowTestRepository()
        let worktree = workflowTestWorktree(repository: repository)
        let definition = WorkflowDefinition.defaultDeliveryDefinition(
            id: "delivery",
            now: Date(timeIntervalSince1970: 100)
        )
        let activeRun = WorkflowRun(
            id: UUID(100),
            definitionID: definition.id,
            workspaceID: worktree.id,
            worktreePath: worktree.workingDirectory.path,
            branchName: worktree.name,
            status: .running,
            currentNodeID: "implement",
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let store = TestStore(
            initialState: workflowTestState(
                repository: repository,
                worktree: worktree,
                definitions: [definition],
                runs: [activeRun]
            )
        ) {
            WindowFeature()
        }

        await store.send(
            .startWorkflowRun(
                workspaceID: worktree.id,
                definitionID: definition.id,
                runID: UUID(101)
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.lastErrorMessage =
                "Workflow run already active for this workspace."
        }
    }

    @Test("Deleting an active workflow run is rejected until it is stopped")
    @MainActor
    func deleteActiveWorkflowRunRejects() async {
        let repository = workflowTestRepository()
        let worktree = workflowTestWorktree(repository: repository)
        let definition = WorkflowDefinition.defaultDeliveryDefinition(
            id: "delivery",
            now: Date(timeIntervalSince1970: 100)
        )
        let activeRun = WorkflowRun(
            id: UUID(100),
            definitionID: definition.id,
            workspaceID: worktree.id,
            worktreePath: worktree.workingDirectory.path,
            branchName: worktree.name,
            status: .running,
            currentNodeID: "implement",
            startedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let store = TestStore(
            initialState: workflowTestState(
                repository: repository,
                worktree: worktree,
                definitions: [definition],
                runs: [activeRun]
            )
        ) {
            WindowFeature()
        }

        await store.send(.deleteWorkflowRun(workspaceID: worktree.id, runID: activeRun.id)) {
            $0.workflowWorkspacesByID[worktree.id]?.lastErrorMessage =
                "Stop the active workflow run before deleting it."
        }
    }

    @Test("Terminal exit auto-transitions single-edge nodes and pauses multi-edge nodes for operator choice")
    @MainActor
    func terminalExitTraversal() async throws {
        let repository = workflowTestRepository()
        let worktree = workflowTestWorktree(repository: repository)
        let definition = WorkflowDefinition.defaultDeliveryDefinition(
            id: "delivery",
            now: Date(timeIntervalSince1970: 100)
        )
        let runID = UUID(100)
        let implementTerminalID = UUID(101)
        let reviewTerminalID = UUID(102)
        let recorder = WorkflowLaunchRecorder()
        let snapshot = workflowTestPlanSnapshot(worktreePath: worktree.workingDirectory.path)
        let reviewNode = try #require(definition.node(id: "review"))
        let reviewer = try #require(definition.worker(id: "reviewer"))
        let reviewPrompt = WorkflowPromptRenderer.renderPrompt(
            definition: definition,
            node: reviewNode,
            worker: reviewer,
            snapshot: snapshot
        )
        let reviewPreview = workflowTestPromptPreview(reviewPrompt)

        let store = TestStore(
            initialState: workflowTestState(
                repository: repository,
                worktree: worktree,
                definitions: [definition],
                runs: [
                    WorkflowRun(
                        id: runID,
                        definitionID: definition.id,
                        workspaceID: worktree.id,
                        worktreePath: worktree.workingDirectory.path,
                        branchName: worktree.name,
                        status: .running,
                        currentNodeID: "implement",
                        activeAttemptID: UUID(200),
                        currentTerminalID: implementTerminalID,
                        latestPlanSnapshot: snapshot,
                        attempts: [
                            WorkflowRunAttempt(
                                id: UUID(200),
                                nodeID: "implement",
                                workerID: "implementer",
                                status: .running,
                                terminalID: implementTerminalID,
                                promptArtifactPath: "/tmp/implement.md",
                                promptPreview: "Implement preview",
                                launchedCommand: "implement command",
                                startedAt: Date(timeIntervalSince1970: 100)
                            )
                        ],
                        startedAt: Date(timeIntervalSince1970: 100),
                        updatedAt: Date(timeIntervalSince1970: 100)
                    )
                ]
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 100)
            $0.uuid = .incrementing
            $0.workflowExecutionClient.startNode = { request in
                await recorder.record(request.node.id)
                return WorkflowNodeLaunchResult(
                    terminalID: reviewTerminalID,
                    launchedCommand: request.prompt,
                    promptArtifactPath: "/tmp/review.md"
                )
            }
        }

        await store.send(
            .workflowExecutionUpdated(
                .terminalExited(runID: runID, terminalID: implementTerminalID)
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].currentNodeID = "review"
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].activeAttemptID = nil
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].currentTerminalID = nil
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[0].status = .completed
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[0].terminalID = nil
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[0].endedAt =
                Date(timeIntervalSince1970: 100)
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].status = .idle
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(0),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Completed Implement. Transitioning via Next."
                )
            )
        }

        await store.receive(.continueWorkflowRun(workspaceID: worktree.id, runID: runID)) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].status = .running
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].activeAttemptID = UUID(1)
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts.append(
                WorkflowRunAttempt(
                    id: UUID(1),
                    nodeID: "review",
                    workerID: "reviewer",
                    status: .running,
                    terminalID: nil,
                    promptArtifactPath: nil,
                    promptPreview: reviewPreview,
                    launchedCommand: nil,
                    startedAt: Date(timeIntervalSince1970: 100),
                    endedAt: nil
                )
            )
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(2),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Launching Review with Reviewer."
                )
            )
        }

        await store.receive(
            .workflowNodeLaunchSucceeded(
                workspaceID: worktree.id,
                runID: runID,
                result: WorkflowNodeLaunchResult(
                    terminalID: reviewTerminalID,
                    launchedCommand: reviewPrompt,
                    promptArtifactPath: "/tmp/review.md"
                )
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].currentTerminalID = reviewTerminalID
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[1].terminalID =
                reviewTerminalID
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[1].promptArtifactPath =
                "/tmp/review.md"
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[1].launchedCommand =
                reviewPrompt
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(3),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Review attached to terminal \(reviewTerminalID.uuidString)."
                )
            )
        }

        await store.send(
            .workflowExecutionUpdated(
                .terminalExited(runID: runID, terminalID: reviewTerminalID)
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].activeAttemptID = nil
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].currentTerminalID = nil
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[1].status = .completed
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[1].terminalID = nil
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].attempts[1].endedAt =
                Date(timeIntervalSince1970: 100)
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].status = .awaitingOperator
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(4),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Completed Review. Choose the next edge."
                )
            )
        }

        await store.send(
            .chooseWorkflowRunEdge(
                workspaceID: worktree.id,
                runID: runID,
                edgeID: "review-to-finish"
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].currentNodeID = "finish"
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].status = .idle
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(5),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Selected Complete."
                )
            )
        }

        await store.receive(.continueWorkflowRun(workspaceID: worktree.id, runID: runID)) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].status = .completed
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].completedAt =
                Date(timeIntervalSince1970: 100)
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(6),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Reached Complete. Workflow finished."
                )
            )
        }

        #expect(await recorder.nodeIDs == ["review"])
    }

    @Test("Workflow follow-up tickets are appended through the persistence client and synced back into the run")
    @MainActor
    func appendWorkflowFollowUpTicket() async {
        let repository = workflowTestRepository()
        let worktree = workflowTestWorktree(repository: repository)
        let definition = WorkflowDefinition.defaultDeliveryDefinition(
            id: "delivery",
            now: Date(timeIntervalSince1970: 100)
        )
        let runID = UUID(100)
        let initialSnapshot = workflowTestPlanSnapshot(worktreePath: worktree.workingDirectory.path)
        let updatedSnapshot = WorkflowPlanSnapshot(
            planFilePath: initialSnapshot.planFilePath,
            phases: [
                WorkflowPlanPhase(
                    id: "phase-1",
                    title: "Phase 1",
                    headingLine: 1,
                    tickets: [
                        WorkflowPlanTicket(
                            id: "line-1",
                            text: "Ship the reducer",
                            isCompleted: false,
                            line: 2,
                            section: .phaseBody
                        ),
                        WorkflowPlanTicket(
                            id: "line-2",
                            text: "Capture relaunch diagnostics",
                            isCompleted: false,
                            line: 5,
                            section: .named("Review Notes")
                        )
                    ]
                )
            ]
        )
        let appendedRequests = LockIsolated<[WorkflowPlanAppendRequest]>([])

        let store = TestStore(
            initialState: workflowTestState(
                repository: repository,
                worktree: worktree,
                definitions: [definition],
                runs: [
                    WorkflowRun(
                        id: runID,
                        definitionID: definition.id,
                        workspaceID: worktree.id,
                        worktreePath: worktree.workingDirectory.path,
                        branchName: worktree.name,
                        status: .awaitingOperator,
                        currentNodeID: "review",
                        latestPlanSnapshot: initialSnapshot,
                        startedAt: Date(timeIntervalSince1970: 100),
                        updatedAt: Date(timeIntervalSince1970: 100)
                    )
                ]
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 100)
            $0.uuid = .incrementing
            $0.workflowPersistenceClient.appendFollowUpTicket = { request, _ in
                appendedRequests.withValue { $0.append(request) }
                return updatedSnapshot
            }
        }

        await store.send(
            .appendWorkflowFollowUpTicket(
                workspaceID: worktree.id,
                runID: runID,
                sectionTitle: "Review Notes",
                text: "Capture relaunch diagnostics"
            )
        )

        await store.receive(
            .workflowFollowUpTicketAppended(
                workspaceID: worktree.id,
                runID: runID,
                snapshot: updatedSnapshot,
                sectionTitle: "Review Notes",
                text: "Capture relaunch diagnostics"
            )
        ) {
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].latestPlanSnapshot = updatedSnapshot
            $0.workflowWorkspacesByID[worktree.id]?.runs[0].events.append(
                WorkflowRunEvent(
                    id: UUID(0),
                    timestamp: Date(timeIntervalSince1970: 100),
                    message: "Appended Review Notes ticket: Capture relaunch diagnostics."
                )
            )
        }

        #expect(appendedRequests.value == [
            WorkflowPlanAppendRequest(
                planFilePath: initialSnapshot.planFilePath,
                phaseIndex: 0,
                sectionTitle: "Review Notes",
                text: "Capture relaunch diagnostics"
            )
        ])
    }
}

private func workflowTestRepository() -> Repository {
    Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-workflow"))
}

private func workflowTestWorktree(repository: Repository) -> Worktree {
    Worktree(
        name: "feature/workflow",
        detail: ".",
        workingDirectory: repository.rootURL.appendingPathComponent("feature-workflow"),
        repositoryRootURL: repository.rootURL
    )
}

private func workflowTestState(
    repository: Repository,
    worktree: Worktree,
    definitions: [WorkflowDefinition],
    runs: [WorkflowRun] = []
) -> WindowFeature.State {
    WindowFeature.State(
        repositories: [repository],
        worktreesByRepository: [repository.id: [worktree]],
        workflowWorkspacesByID: [
            worktree.id: WindowFeature.WorkflowWorkspaceState(
                definitions: definitions,
                runs: runs
            )
        ],
        selectedRepositoryID: repository.id,
        selectedWorkspaceID: worktree.id
    )
}

private func workflowTestPlanSnapshot(worktreePath: String) -> WorkflowPlanSnapshot {
    WorkflowPlanSnapshot(
        planFilePath: "\(worktreePath)/plan.md",
        phases: [
            WorkflowPlanPhase(
                id: "phase-1",
                title: "Phase 1",
                headingLine: 1,
                tickets: [
                    WorkflowPlanTicket(
                        id: "line-1",
                        text: "Ship the reducer",
                        isCompleted: false,
                        line: 2,
                        section: .phaseBody
                    )
                ]
            )
        ]
    )
}

private func workflowTestPromptPreview(
    _ prompt: String
) -> String {
    let collapsed = prompt
        .replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    if collapsed.count <= 200 {
        return collapsed
    }
    let index = collapsed.index(collapsed.startIndex, offsetBy: 200)
    return "\(collapsed[..<index])..."
}

private actor WorkflowLaunchRecorder {
    private(set) var nodeIDs: [String] = []

    func record(_ nodeID: String) {
        nodeIDs.append(nodeID)
    }
}
