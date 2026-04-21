import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func reduceReviewIssueAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .setReviewIssueInvestigationRequest(let request):
            state.reviewIssueInvestigationRequest = request
            return .none
        case let .setReviewRunFollowUpHarness(workspaceID, runID, harness):
            return updateReviewRun(state: &state, workspaceID: workspaceID, runID: runID) { run in
                run.profile.followUpHarness = harness
            }
        case let .dismissReviewIssue(workspaceID, runID, issueID):
            return updateReviewIssue(state: &state, workspaceID: workspaceID, runID: runID, issueID: issueID) { issue in
                issue.status = .dismissed
            }
        case let .acceptReviewIssueRisk(workspaceID, runID, issueID):
            return updateReviewIssue(state: &state, workspaceID: workspaceID, runID: runID, issueID: issueID) { issue in
                issue.status = .acceptedRisk
            }
        case let .investigateReviewIssue(workspaceID, runID, issueID, harness):
            return prepareReviewIssueInvestigation(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                issueID: issueID,
                harness: harness
            )
        case let .reviewIssueInvestigationPrepared(workspaceID, runID, draft):
            return applyReviewIssueInvestigationPrepared(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                draft: draft
            )
        case let .reviewIssueInvestigationFailed(workspaceID, _, _, message):
            state.lastErrorMessage = message
            state.updateReviewWorkspace(workspaceID) { workspaceState in
                workspaceState.lastErrorMessage = message
            }
            return .none
        default:
            return .none
        }
    }

    func updateReviewRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        update: (inout ReviewRun) -> Void
    ) -> Effect<Action> {
        guard let worktree = state.worktree(for: workspaceID),
              var run = state.reviewRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        let issues = state.reviewIssues(workspaceID: workspaceID, runID: runID)
        update(&run)

        state.updateReviewWorkspace(workspaceID) { workspaceState in
            workspaceState.lastErrorMessage = nil
            upsertReviewRun(run, in: &workspaceState)
        }

        return syncReviewRunPersistenceEffect(
            run: run,
            issues: issues,
            rootURL: worktree.repositoryRootURL
        )
    }

    func updateReviewIssue(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        issueID: UUID,
        update: (inout ReviewIssue) -> Void
    ) -> Effect<Action> {
        guard let persisted = mutateReviewRunIssues(
            state: &state,
            workspaceID: workspaceID,
            runID: runID,
            issueID: issueID,
            update: update
        ) else {
            return .none
        }

        return syncReviewRunPersistenceEffect(
            run: persisted.run,
            issues: persisted.issues,
            rootURL: persisted.rootURL
        )
    }

    func prepareReviewIssueInvestigation(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        issueID: UUID,
        harness: BuiltInLauncherKind
    ) -> Effect<Action> {
        state.lastErrorMessage = nil

        guard let worktree = state.worktree(for: workspaceID),
              let run = state.reviewRun(workspaceID: workspaceID, runID: runID),
              let issue = state.reviewIssues(workspaceID: workspaceID, runID: runID)
              .first(where: { $0.id == issueID }) else {
            state.lastErrorMessage = "The selected review issue is no longer available."
            return .none
        }

        let settings = reviewSettings(for: worktree)
        state.reviewIssueInvestigationRequest = WindowFeature.ReviewIssueInvestigationRequest(
            id: uuid(),
            workspaceID: workspaceID,
            runID: runID,
            issueID: issueID,
            repositoryRootURL: worktree.repositoryRootURL,
            workingDirectoryURL: worktree.workingDirectory,
            harness: harness,
            launcher: makeReviewInvestigationLauncher(settings: settings, harness: harness),
            prompt: makeReviewInvestigationPrompt(
                run: run,
                issue: issue,
                workspaceName: worktree.name,
                additionalInstructions: settings.review.additionalInstructions
            )
        )
        return .none
    }

    func applyReviewIssueInvestigationPrepared(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        draft: ReviewFixDraft
    ) -> Effect<Action> {
        guard let persisted = mutateReviewRunIssues(
            state: &state,
            workspaceID: workspaceID,
            runID: runID,
            issueID: draft.issueID,
            update: { issue in
                issue.status = .followUpPrepared
                issue.followUpPromptArtifactPath = draft.promptArtifactPath
            }
        ) else {
            return .none
        }

        state.lastErrorMessage = nil
        state.updateReviewWorkspace(workspaceID) { workspaceState in
            workspaceState.lastErrorMessage = nil
        }

        return syncReviewRunPersistenceEffect(
            run: persisted.run,
            issues: persisted.issues,
            rootURL: persisted.rootURL
        )
    }

    func mutateReviewRunIssues(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        issueID: UUID,
        update: (inout ReviewIssue) -> Void
    ) -> (run: ReviewRun, issues: [ReviewIssue], rootURL: URL)? {
        guard let worktree = state.worktree(for: workspaceID),
              var run = state.reviewRun(workspaceID: workspaceID, runID: runID) else {
            return nil
        }

        var issues = state.reviewIssues(workspaceID: workspaceID, runID: runID)
        guard let issueIndex = issues.firstIndex(where: { $0.id == issueID }) else {
            return nil
        }

        update(&issues[issueIndex])
        issues.sort(by: reviewIssueSort)

        run.issueIDs = issues.map(\.id)
        run.issueCounts = reviewIssueCounts(from: issues)
        run.overallRisk = reviewOverallRisk(from: issues.filter(reviewIssueNeedsAttention))

        state.updateReviewWorkspace(workspaceID) { workspaceState in
            workspaceState.lastErrorMessage = nil
            upsertReviewRun(run, in: &workspaceState)
            workspaceState.issuesByRunID[runID] = issues
        }

        return (run, issues, worktree.repositoryRootURL)
    }

    func makeReviewInvestigationLauncher(
        settings: RepositorySettings,
        harness: BuiltInLauncherKind
    ) -> LauncherTemplate {
        var launcher = switch harness {
        case .claude:
            settings.claudeLauncher
        case .codex:
            settings.codexLauncher
        }

        let reviewSettings = settings.review
        if let model = normalizedReviewSettingValue(reviewSettings.followUpModelOverride) {
            launcher.model = model
        }
        if let reasoning = normalizedReviewSettingValue(reviewSettings.followUpReasoningOverride) {
            launcher.reasoningLevel = reasoning
        }
        if let dangerousPermissions = reviewSettings.followUpDangerousPermissionsOverride {
            launcher.dangerousPermissions = dangerousPermissions
        }
        launcher.executionBehavior = .stageInTerminal
        return launcher
    }

    func makeReviewInvestigationPrompt(
        run: ReviewRun,
        issue: ReviewIssue,
        workspaceName: String,
        additionalInstructions: String?
    ) -> String {
        var lines = reviewInvestigationContextLines(
            run: run,
            issue: issue,
            workspaceName: workspaceName
        )

        lines.append(contentsOf: reviewInvestigationInstructionLines())

        if let additionalInstructions = normalizedReviewSettingValue(additionalInstructions) {
            lines.append(contentsOf: [
                "",
                "Repository-specific review instructions",
                additionalInstructions
            ])
        }

        return lines.joined(separator: "\n")
    }
}

private func reviewInvestigationContextLines(
    run: ReviewRun,
    issue: ReviewIssue,
    workspaceName: String
) -> [String] {
    var lines: [String] = [
        "# Review Fix",
        "",
        "You are fixing a structured review finding for the Devys workspace `\(workspaceName)`.",
        "",
        "Context",
        "- Review target: \(run.target.displayTitle)",
        "- Original trigger: \(run.trigger.source.rawValue)",
        "- Audit harness: \(run.profile.auditHarness.rawValue)",
        "- Review run ID: \(run.id.uuidString)",
        "- Review issue ID: \(issue.id.uuidString)",
        "",
        "Finding",
        "- Severity: \(issue.severity.rawValue)",
        "- Confidence: \(issue.confidence.rawValue)",
        "- Title: \(issue.title)",
        "- Summary: \(issue.summary)",
        "- Rationale: \(issue.rationale)"
    ]

    if !issue.paths.isEmpty {
        lines.append("- Paths: \(issue.paths.joined(separator: ", "))")
    }
    if !issue.locations.isEmpty {
        lines.append("- Locations: \(issue.locations.map(\.label).joined(separator: ", "))")
    }
    if !issue.sourceReferences.isEmpty {
        lines.append("- Sources: \(issue.sourceReferences.joined(separator: ", "))")
    }

    return lines
}

private func reviewInvestigationInstructionLines() -> [String] {
    [
            "",
            "Instructions",
            "1. Confirm whether this finding is real.",
            "2. If it is real, implement the smallest correct fix now.",
            "3. If it is a false positive or should be deferred, explain why and do not make unrelated changes.",
            "4. Keep the patch focused on this finding and preserve explicit ownership boundaries.",
            "5. Summarize what changed and what you verified before you finish.",
            "",
            "Response format",
            "- Verdict: fixed | false-positive | defer",
            "- Changes: concise list or `none`",
            "- Validation: what you checked",
            "- Notes: anything still risky or deferred"
    ]
}

private func normalizedReviewSettingValue(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension ReviewIssueLocation {
    var label: String {
        var result = path
        if let line {
            result += ":\(line)"
        }
        if let column {
            result += ":\(column)"
        }
        return result
    }
}
