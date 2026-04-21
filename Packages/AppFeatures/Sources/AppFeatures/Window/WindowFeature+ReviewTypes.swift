import Foundation
import Git
import Workspace

public extension WindowFeature {
    struct ReviewEntryPresentation: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var repositoryRootURL: URL
        public var workspaceName: String
        public var branchName: String
        public var pullRequestNumber: Int?
        public var pullRequestTitle: String?
        public var availableTargets: [ReviewTargetKind]

        public init(
            id: UUID = UUID(),
            workspaceID: Workspace.ID,
            repositoryRootURL: URL,
            workspaceName: String,
            branchName: String,
            pullRequestNumber: Int? = nil,
            pullRequestTitle: String? = nil,
            availableTargets: [ReviewTargetKind] = ReviewTargetKind.manualEntryTargets
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.repositoryRootURL = repositoryRootURL
            self.workspaceName = workspaceName
            self.branchName = branchName
            self.pullRequestNumber = pullRequestNumber
            self.pullRequestTitle = pullRequestTitle
            self.availableTargets = availableTargets
        }
    }

    struct ReviewIssueInvestigationRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var runID: UUID
        public var issueID: UUID
        public var repositoryRootURL: URL
        public var workingDirectoryURL: URL
        public var harness: BuiltInLauncherKind
        public var launcher: LauncherTemplate
        public var prompt: String

        public init(
            id: UUID = UUID(),
            workspaceID: Workspace.ID,
            runID: UUID,
            issueID: UUID,
            repositoryRootURL: URL,
            workingDirectoryURL: URL,
            harness: BuiltInLauncherKind,
            launcher: LauncherTemplate,
            prompt: String
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.runID = runID
            self.issueID = issueID
            self.repositoryRootURL = repositoryRootURL
            self.workingDirectoryURL = workingDirectoryURL
            self.harness = harness
            self.launcher = launcher
            self.prompt = prompt
        }
    }

    struct ReviewWorkspaceState: Equatable, Sendable {
        public var runs: [ReviewRun]
        public var issuesByRunID: [UUID: [ReviewIssue]]
        public var isLoading: Bool
        public var lastErrorMessage: String?

        public init(
            runs: [ReviewRun] = [],
            issuesByRunID: [UUID: [ReviewIssue]] = [:],
            isLoading: Bool = false,
            lastErrorMessage: String? = nil
        ) {
            self.runs = runs
            self.issuesByRunID = issuesByRunID
            self.isLoading = isLoading
            self.lastErrorMessage = lastErrorMessage
        }

        public func run(id: UUID) -> ReviewRun? {
            runs.first { $0.id == id }
        }

        public func issues(for runID: UUID) -> [ReviewIssue] {
            issuesByRunID[runID] ?? []
        }
    }
}

public extension WindowFeature.State {
    mutating func updateReviewWorkspace(
        _ workspaceID: Workspace.ID,
        _ update: (inout WindowFeature.ReviewWorkspaceState) -> Void
    ) {
        var workspaceState = reviewWorkspaceState(for: workspaceID)
        update(&workspaceState)
        workspaceState.runs.sort(by: ReviewRun.sort)
        reviewWorkspacesByID[workspaceID] = workspaceState
    }

    func reviewWorkspaceState(
        for workspaceID: Workspace.ID
    ) -> WindowFeature.ReviewWorkspaceState {
        reviewWorkspacesByID[workspaceID] ?? WindowFeature.ReviewWorkspaceState()
    }

    func reviewRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> ReviewRun? {
        reviewWorkspacesByID[workspaceID]?.run(id: runID)
    }

    func reviewIssues(
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> [ReviewIssue] {
        reviewWorkspacesByID[workspaceID]?.issues(for: runID) ?? []
    }

    func reviewPresentation(
        for worktree: Worktree,
        id: UUID = UUID()
    ) -> WindowFeature.ReviewEntryPresentation {
        let pullRequest = operational.metadataEntriesByWorkspaceID[worktree.id]?.pullRequest
        let availableTargets = pullRequest.map { _ in
            ReviewTargetKind.manualEntryTargets + [.pullRequest]
        } ?? ReviewTargetKind.manualEntryTargets
        return WindowFeature.ReviewEntryPresentation(
            id: id,
            workspaceID: worktree.id,
            repositoryRootURL: worktree.repositoryRootURL,
            workspaceName: worktree.name,
            branchName: worktree.name,
            pullRequestNumber: pullRequest?.number,
            pullRequestTitle: pullRequest?.title,
            availableTargets: availableTargets
        )
    }
}
