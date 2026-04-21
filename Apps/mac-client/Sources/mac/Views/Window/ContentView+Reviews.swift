import AppFeatures
import Foundation
import UI
import Workspace

@MainActor
extension ContentView {
    func reviewWorkspaceState(
        for workspaceID: Workspace.ID
    ) -> WindowFeature.ReviewWorkspaceState {
        store.reviewWorkspacesByID[workspaceID] ?? WindowFeature.ReviewWorkspaceState()
    }

    func reviewRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> ReviewRun? {
        store.reviewWorkspacesByID[workspaceID]?.run(id: runID)
    }

    func reviewIssues(
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> [ReviewIssue] {
        store.reviewWorkspacesByID[workspaceID]?.issues(for: runID) ?? []
    }

    func reviewRunForContent(
        _ content: WorkspaceTabContent?
    ) -> ReviewRun? {
        guard case .reviewRun(let workspaceID, let runID) = content else {
            return nil
        }
        return reviewRun(workspaceID: workspaceID, runID: runID)
    }

    func reviewIssuesForContent(
        _ content: WorkspaceTabContent?
    ) -> [ReviewIssue] {
        guard case .reviewRun(let workspaceID, let runID) = content else {
            return []
        }
        return reviewIssues(workspaceID: workspaceID, runID: runID)
    }

    func executeReviewIssueInvestigation(
        _ request: WindowFeature.ReviewIssueInvestigationRequest
    ) async {
        do {
            let promptArtifactURL = try writeReviewInvestigationPromptArtifact(request)
            let command = try makeReviewInvestigationCommand(
                request: request,
                promptArtifactURL: promptArtifactURL
            )
            try await launchReviewInvestigationTerminal(
                request: request,
                command: command
            )

            store.send(
                .reviewIssueInvestigationPrepared(
                    workspaceID: request.workspaceID,
                    runID: request.runID,
                    draft: ReviewFixDraft(
                        issueID: request.issueID,
                        harness: request.harness,
                        resolvedCommandPreview: command,
                        promptArtifactPath: promptArtifactURL.path
                    )
                )
            )
            persistTerminalRelaunchSnapshotIfNeeded()
        } catch {
            store.send(
                .reviewIssueInvestigationFailed(
                    workspaceID: request.workspaceID,
                    runID: request.runID,
                    issueID: request.issueID,
                    message: error.localizedDescription
                )
            )
            showLauncherUnavailableAlert(
                title: "Review Fix Failed",
                message: error.localizedDescription
            )
        }
    }

    func rerunReview(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        store.send(.rerunReview(workspaceID: workspaceID, runID: runID))
    }

    func openReviewIssueFile(
        workspaceID: Workspace.ID,
        issue: ReviewIssue
    ) {
        guard let path = reviewIssuePrimaryPath(issue),
              !path.isEmpty else {
            return
        }
        openReviewArtifact(workspaceID: workspaceID, path: path)
    }

    func openReviewArtifact(
        workspaceID: Workspace.ID,
        path: String
    ) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              let worktree = windowWorkspaceContext(for: workspaceID)?.worktree else {
            return
        }

        let url: URL
        if trimmedPath.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmedPath)
        } else {
            url = worktree.workingDirectory.appendingPathComponent(trimmedPath, isDirectory: false)
        }

        openInPermanentTab(content: .editor(workspaceID: workspaceID, url: url.standardizedFileURL))
    }

    private func launchReviewInvestigationTerminal(
        request: WindowFeature.ReviewIssueInvestigationRequest,
        command: String
    ) async throws {
        guard let worktree = windowWorkspaceContext(for: request.workspaceID)?.worktree else {
            throw NSError(
                domain: "DevysReviewInvestigation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Select a local workspace before starting an investigation."]
            )
        }

        let session = createPendingHostedTerminalSession(
            in: request.workspaceID,
            workingDirectory: request.workingDirectoryURL,
            stagedCommand: command,
            tabIcon: reviewHarnessTabIcon(request.harness),
            traceSource: "review-investigation",
            launchProfile: launcherTerminalLaunchProfile(for: request.harness),
            openMode: "permanent"
        )
        try presentHostedTerminalTab(
            session: session,
            workspaceID: request.workspaceID,
            preferredPaneID: nil,
            failureMessage: "Could not open a terminal tab for the review investigation."
        )
        try await startPendingHostedTerminalSession(
            session,
            in: request.workspaceID,
            workingDirectory: worktree.workingDirectory,
            launchProfile: launcherTerminalLaunchProfile(for: request.harness),
            traceSource: "review-investigation"
        )
    }

    private func writeReviewInvestigationPromptArtifact(
        _ request: WindowFeature.ReviewIssueInvestigationRequest
    ) throws -> URL {
        let fileManager = FileManager.default
        let promptsDirectoryURL = ReviewStorageLocations.promptsDirectory(
            for: request.repositoryRootURL,
            runID: request.runID,
            fileManager: fileManager
        )
        try fileManager.createDirectory(at: promptsDirectoryURL, withIntermediateDirectories: true)

        let fileName =
            "fix-\(reviewPromptTimestamp())-" +
            "\(request.harness.rawValue)-" +
            "\(request.issueID.uuidString).md"
        let promptURL = promptsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        try request.prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        return promptURL
    }

    private func makeReviewInvestigationCommand(
        request: WindowFeature.ReviewIssueInvestigationRequest,
        promptArtifactURL: URL
    ) throws -> String {
        let resolvedCommand = try RepositoryLaunchPlanner.resolveLauncher(
            request.launcher,
            kind: request.harness
        )
        let promptExpression = "\"$(cat \(shellQuoted(promptArtifactURL.path)))\""
        return "\(resolvedCommand.command) \(promptExpression)"
    }

    private func reviewIssuePrimaryPath(
        _ issue: ReviewIssue
    ) -> String? {
        issue.locations.first?.path ?? issue.paths.first
    }
}

private func reviewPromptTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
}

private func reviewHarnessTabIcon(
    _ harness: BuiltInLauncherKind
) -> String {
    switch harness {
    case .claude:
        DevysIconName.claudeCode
    case .codex:
        DevysIconName.codex
    }
}
