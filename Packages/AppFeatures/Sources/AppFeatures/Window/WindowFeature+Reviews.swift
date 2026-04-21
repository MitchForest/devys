import ComposableArchitecture
import Foundation
import Git
import Split
import Workspace

extension WindowFeature {
    func reduceReviewAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .reviewWorkspaceLoadRequested,
             .reviewWorkspaceLoaded,
             .reviewWorkspaceLoadFailed:
            return reduceReviewWorkspaceAction(state: &state, action: action)

        case let .reviewTriggerIngressReceived(request):
            return startTriggeredReviewEffect(
                state: &state,
                request: request
            )

        case let .startManualReview(workspaceID, targetKind):
            return startManualReviewEffect(
                state: &state,
                workspaceID: workspaceID,
                targetKind: targetKind
            )

        case let .rerunReview(workspaceID, runID):
            return rerunReviewEffect(
                state: &state,
                workspaceID: workspaceID,
                runID: runID
            )

        case let .reviewExecutionFinished(workspaceID, runID, result):
            return applyReviewExecutionResult(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                result: result
            )

        case let .deleteReviewRun(workspaceID, runID):
            return deleteReviewRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID
            )

        default:
            return reduceReviewIssueAction(state: &state, action: action)
        }
    }
}

extension WindowFeature {
    struct ManualReviewLaunch {
        let runID: UUID
        let run: ReviewRun
        let request: ReviewExecutionRequest
    }

    func startManualReviewEffect(
        state: inout State,
        workspaceID: Workspace.ID,
        targetKind: ReviewTargetKind
    ) -> Effect<Action> {
        state.lastErrorMessage = nil
        state.reviewEntryPresentation = nil

        guard let worktree = state.worktree(for: workspaceID) else {
            state.lastErrorMessage = "Select a local workspace to review."
            return .none
        }

        let settings = reviewSettings(for: worktree)
        guard settings.review.isEnabled else {
            state.lastErrorMessage = "Review is disabled for this repository."
            return .none
        }

        let pullRequest = state.operational.metadataEntriesByWorkspaceID[workspaceID]?.pullRequest
        let trigger = manualReviewTrigger()
        guard let target = makeManualReviewTarget(
            kind: targetKind,
            worktree: worktree,
            pullRequest: pullRequest
        ) else {
            state.lastErrorMessage = reviewLaunchFailureMessage(for: targetKind)
            return .none
        }

        let launch = makeReviewLaunch(
            workspaceID: workspaceID,
            worktree: worktree,
            target: target,
            trigger: trigger,
            settings: settings.review,
            createdAt: trigger.createdAt
        )

        state.updateReviewWorkspace(workspaceID) { workspaceState in
            workspaceState.lastErrorMessage = nil
            upsertReviewRun(launch.run, in: &workspaceState)
            workspaceState.issuesByRunID[launch.runID] = []
        }
        openReviewRunTab(
            state: &state,
            workspaceID: workspaceID,
            runID: launch.runID
        )

        return reviewExecutionEffect(
            workspaceID: workspaceID,
            runID: launch.runID,
            request: launch.request
        )
    }

    func rerunReviewEffect(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> Effect<Action> {
        state.lastErrorMessage = nil

        guard let worktree = state.worktree(for: workspaceID),
              let existingRun = state.reviewRun(workspaceID: workspaceID, runID: runID) else {
            state.lastErrorMessage = "The selected review run is no longer available."
            return .none
        }

        let settings = reviewSettings(for: worktree)
        guard settings.review.isEnabled else {
            state.lastErrorMessage = "Review is disabled for this repository."
            return .none
        }

        let trigger = manualReviewTrigger()
        let launch = makeReviewLaunch(
            workspaceID: workspaceID,
            worktree: worktree,
            target: normalizedReviewTarget(existingRun.target, worktree: worktree),
            trigger: trigger,
            settings: settings.review,
            createdAt: trigger.createdAt
        )

        state.updateReviewWorkspace(workspaceID) { workspaceState in
            workspaceState.lastErrorMessage = nil
            upsertReviewRun(launch.run, in: &workspaceState)
            workspaceState.issuesByRunID[launch.runID] = []
        }
        openReviewRunTab(
            state: &state,
            workspaceID: workspaceID,
            runID: launch.runID
        )

        return reviewExecutionEffect(
            workspaceID: workspaceID,
            runID: launch.runID,
            request: launch.request
        )
    }

    func startTriggeredReviewEffect(
        state: inout State,
        request: ReviewTriggerRequest
    ) -> Effect<Action> {
        guard let worktree = state.triggeredReviewWorktree(for: request) else {
            return .none
        }

        let settings = reviewSettings(for: worktree)
        guard settings.review.isEnabled,
              reviewTriggerIsEnabled(
                request.trigger.source,
                settings: settings.review
              )
        else {
            return .none
        }

        let launch = makeTriggeredReviewLaunch(
            worktree: worktree,
            request: request,
            settings: settings.review
        )

        state.updateReviewWorkspace(worktree.id) { workspaceState in
            workspaceState.lastErrorMessage = nil
            upsertReviewRun(launch.run, in: &workspaceState)
            workspaceState.issuesByRunID[launch.runID] = []
        }

        return reviewExecutionEffect(
            workspaceID: worktree.id,
            runID: launch.runID,
            request: launch.request
        )
    }

    func applyReviewExecutionResult(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        result: TaskResult<ReviewExecutionResult>
    ) -> Effect<Action> {
        guard let worktree = state.worktree(for: workspaceID),
              var run = state.reviewRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        switch result {
        case .success(let executionResult):
            let issues = normalizedReviewIssues(
                executionResult.issues,
                runID: runID
            ).sorted(by: reviewIssueSort)

            run.status = .completed
            run.artifactSet = executionResult.artifactSet
            run.overallRisk = executionResult.overallRisk ?? reviewOverallRisk(from: issues)
            run.issueIDs = issues.map(\.id)
            run.issueCounts = reviewIssueCounts(from: issues)
            run.completedAt = now
            run.lastErrorMessage = nil

            state.updateReviewWorkspace(workspaceID) { workspaceState in
                workspaceState.lastErrorMessage = nil
                upsertReviewRun(run, in: &workspaceState)
                workspaceState.issuesByRunID[runID] = issues
            }

            return syncReviewRunPersistenceEffect(
                run: run,
                issues: issues,
                rootURL: worktree.repositoryRootURL
            )

        case .failure(let error):
            run.status = .failed
            if let failure = error as? ReviewExecutionFailure {
                run.artifactSet = failure.artifactSet
            }
            run.issueIDs = []
            run.issueCounts = ReviewIssueCounts()
            run.completedAt = now
            run.lastErrorMessage = error.localizedDescription

            state.updateReviewWorkspace(workspaceID) { workspaceState in
                workspaceState.lastErrorMessage = error.localizedDescription
                upsertReviewRun(run, in: &workspaceState)
                workspaceState.issuesByRunID[runID] = []
            }

            return syncReviewRunPersistenceEffect(
                run: run,
                issues: [],
                rootURL: worktree.repositoryRootURL
            )
        }
    }

    func syncReviewRunPersistenceEffect(
        run: ReviewRun,
        issues: [ReviewIssue],
        rootURL: URL
    ) -> Effect<Action> {
        if reviewRunShouldPersist(run) {
            return persistReviewRunEffect(run: run, issues: issues, rootURL: rootURL)
        }
        return deleteReviewRunEffect(runID: run.id, rootURL: rootURL)
    }

    func persistReviewRunEffect(
        run: ReviewRun,
        issues: [ReviewIssue],
        rootURL: URL
    ) -> Effect<Action> {
        let reviewPersistenceClient = self.reviewPersistenceClient
        return .run { _ in
            try await reviewPersistenceClient.saveRun(run, issues, rootURL)
        }
    }

    func deleteReviewRunEffect(
        runID: UUID,
        rootURL: URL
    ) -> Effect<Action> {
        let reviewPersistenceClient = self.reviewPersistenceClient
        return .run { _ in
            try await reviewPersistenceClient.deleteRun(runID, rootURL)
        }
    }

    func deleteReviewRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> Effect<Action> {
        guard let rootURL = state.worktree(for: workspaceID)?.repositoryRootURL,
              state.reviewRun(workspaceID: workspaceID, runID: runID) != nil else {
            return .none
        }

        state.updateReviewWorkspace(workspaceID) { workspaceState in
            workspaceState.runs.removeAll { $0.id == runID }
            workspaceState.issuesByRunID.removeValue(forKey: runID)
            workspaceState.lastErrorMessage = nil
        }

        return deleteReviewRunEffect(runID: runID, rootURL: rootURL)
    }

    func reviewSettings(
        for worktree: Worktree
    ) -> RepositorySettings {
        let repositorySettingsClient = self.repositorySettingsClient
        return MainActor.assumeIsolated {
            repositorySettingsClient.load(worktree.repositoryRootURL)
        }
    }

    func makeReviewLaunch(
        workspaceID: Workspace.ID,
        worktree: Worktree,
        target: ReviewTarget,
        trigger: ReviewTrigger,
        settings: ReviewSettings,
        createdAt: Date
    ) -> ManualReviewLaunch {
        let runID = uuid()
        let profile = ReviewProfile(settings: settings)
        let run = ReviewRun(
            id: runID,
            target: target,
            trigger: trigger,
            profile: profile,
            status: .running,
            createdAt: createdAt,
            startedAt: now
        )
        let request = ReviewExecutionRequest(
            runID: runID,
            workspaceID: workspaceID,
            workingDirectoryURL: worktree.workingDirectory,
            target: target,
            trigger: trigger,
            profile: profile
        )

        return ManualReviewLaunch(
            runID: runID,
            run: run,
            request: request
        )
    }

    func makeTriggeredReviewLaunch(
        worktree: Worktree,
        request: ReviewTriggerRequest,
        settings: ReviewSettings
    ) -> ManualReviewLaunch {
        makeReviewLaunch(
            workspaceID: worktree.id,
            worktree: worktree,
            target: normalizedReviewTarget(request.target, worktree: worktree),
            trigger: request.trigger,
            settings: settings,
            createdAt: request.trigger.createdAt
        )
    }

    func reviewExecutionEffect(
        workspaceID: Workspace.ID,
        runID: UUID,
        request: ReviewExecutionRequest
    ) -> Effect<Action> {
        let reviewExecutionClient = self.reviewExecutionClient
        return .run { send in
            await send(
                .reviewExecutionFinished(
                    workspaceID: workspaceID,
                    runID: runID,
                    result: TaskResult {
                        try await reviewExecutionClient.run(request)
                    }
                )
            )
        }
    }

    func openReviewRunTab(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        let shell = state.workspaceShells[workspaceID]
            ?? WindowFeature.WorkspaceShell(activeSidebar: state.activeSidebar)
        let layout = shell.layout ?? WindowFeature.WorkspaceLayout()
        let paneID = shell.focusedPaneID ?? layout.focusedFallbackPaneID ?? PaneID()
        _ = state.openWorkspaceContent(
            workspaceID: workspaceID,
            paneID: paneID,
            content: .reviewRun(workspaceID: workspaceID, runID: runID),
            mode: .permanent
        )
    }

    func makeManualReviewTarget(
        kind: ReviewTargetKind,
        worktree: Worktree,
        pullRequest: PullRequest?
    ) -> ReviewTarget? {
        switch kind {
        case .currentBranch:
            return ReviewTarget(
                id: "\(worktree.id):\(kind.rawValue)",
                kind: kind,
                workspaceID: worktree.id,
                repositoryRootURL: worktree.repositoryRootURL,
                title: worktree.name,
                branchName: worktree.name
            )

        case .unstagedChanges,
             .stagedChanges,
             .lastCommit:
            return ReviewTarget(
                id: "\(worktree.id):\(kind.rawValue)",
                kind: kind,
                workspaceID: worktree.id,
                repositoryRootURL: worktree.repositoryRootURL,
                title: kind.displayTitle,
                branchName: worktree.name
            )

        case .pullRequest:
            guard let pullRequest else { return nil }
            let title = reviewPullRequestTitle(pullRequest)
            return ReviewTarget(
                id: "\(worktree.id):\(kind.rawValue):\(pullRequest.number)",
                kind: kind,
                workspaceID: worktree.id,
                repositoryRootURL: worktree.repositoryRootURL,
                title: title,
                branchName: pullRequest.headBranch,
                baseBranchName: pullRequest.baseBranch,
                pullRequestNumber: pullRequest.number
            )

        case .commitRange,
             .selection:
            return ReviewTarget(
                id: "\(worktree.id):\(kind.rawValue)",
                kind: kind,
                workspaceID: worktree.id,
                repositoryRootURL: worktree.repositoryRootURL,
                title: kind.displayTitle,
                branchName: worktree.name
            )
        }
    }
}

private extension WindowFeature {
    func manualReviewTrigger() -> ReviewTrigger {
        ReviewTrigger(
            id: uuid(),
            source: .manual,
            createdAt: now,
            isUserVisible: true
        )
    }
}

private func normalizedReviewTarget(
    _ target: ReviewTarget,
    worktree: Worktree
) -> ReviewTarget {
    var normalized = target
    normalized.workspaceID = worktree.id
    normalized.repositoryRootURL = worktree.repositoryRootURL
    normalized.branchName = normalized.branchName ?? worktree.name
    if normalized.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        normalized.id = "\(worktree.id):\(target.kind.rawValue)"
    }
    return normalized
}

private func reviewLaunchFailureMessage(
    for targetKind: ReviewTargetKind
) -> String {
    switch targetKind {
    case .pullRequest:
        return "No open pull request is mapped to this workspace."
    case .commitRange, .selection:
        return "\(targetKind.displayTitle) review is not available yet."
    case .unstagedChanges, .stagedChanges, .lastCommit, .currentBranch:
        return "Unable to start the selected review target."
    }
}

private func reviewPullRequestTitle(
    _ pullRequest: PullRequest
) -> String {
    let trimmedTitle = pullRequest.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedTitle.isEmpty == false else {
        return "Pull Request #\(pullRequest.number)"
    }
    return "#\(pullRequest.number) \(trimmedTitle)"
}

private extension WindowFeature.State {
    func triggeredReviewWorktree(
        for request: ReviewTriggerRequest
    ) -> Worktree? {
        if let worktree = worktree(for: request.workspaceID) {
            return worktree
        }

        let normalizedRootURL = request.repositoryRootURL.standardizedFileURL
        let matchingWorktrees = worktreesByRepository.values
            .flatMap { $0 }
            .filter { $0.repositoryRootURL.standardizedFileURL == normalizedRootURL }

        return matchingWorktrees.first(where: \.isPrimary) ?? matchingWorktrees.first
    }
}

private func reviewTriggerIsEnabled(
    _ source: ReviewTriggerSource,
    settings: ReviewSettings
) -> Bool {
    switch source {
    case .postCommitHook:
        return settings.reviewOnCommit
    case .pullRequestHook:
        return settings.reviewOnPullRequestUpdates
    case .manual,
         .pullRequestCommand,
         .workspaceOpen,
         .scheduled,
         .remoteHost:
        return true
    }
}
