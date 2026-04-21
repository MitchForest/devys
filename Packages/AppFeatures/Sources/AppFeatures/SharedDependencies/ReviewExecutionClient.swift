import Dependencies
import Foundation
import Workspace

public struct ReviewExecutionRequest: Equatable, Sendable {
    public var runID: UUID
    public var workspaceID: Workspace.ID?
    public var workingDirectoryURL: URL
    public var target: ReviewTarget
    public var trigger: ReviewTrigger
    public var profile: ReviewProfile

    public init(
        runID: UUID,
        workspaceID: Workspace.ID?,
        workingDirectoryURL: URL,
        target: ReviewTarget,
        trigger: ReviewTrigger,
        profile: ReviewProfile
    ) {
        self.runID = runID
        self.workspaceID = workspaceID
        self.workingDirectoryURL = workingDirectoryURL
        self.target = target
        self.trigger = trigger
        self.profile = profile
    }
}

public struct ReviewExecutionResult: Equatable, Sendable {
    public var artifactSet: ReviewArtifactSet
    public var overallRisk: ReviewOverallRisk?
    public var issues: [ReviewIssue]
    public var rawOutputPreview: String?

    public init(
        artifactSet: ReviewArtifactSet = ReviewArtifactSet(),
        overallRisk: ReviewOverallRisk? = nil,
        issues: [ReviewIssue] = [],
        rawOutputPreview: String? = nil
    ) {
        self.artifactSet = artifactSet
        self.overallRisk = overallRisk
        self.issues = issues
        self.rawOutputPreview = rawOutputPreview
    }
}

public struct ReviewExecutionFailure: LocalizedError, Equatable, Sendable {
    public var message: String
    public var artifactSet: ReviewArtifactSet
    public var rawOutputPreview: String?

    public init(
        message: String,
        artifactSet: ReviewArtifactSet = ReviewArtifactSet(),
        rawOutputPreview: String? = nil
    ) {
        self.message = message
        self.artifactSet = artifactSet
        self.rawOutputPreview = rawOutputPreview
    }

    public var errorDescription: String? {
        message
    }
}

public struct ReviewExecutionClient: Sendable {
    public var run: @MainActor @Sendable (ReviewExecutionRequest) async throws -> ReviewExecutionResult

    public init(
        run: @escaping @MainActor @Sendable (ReviewExecutionRequest) async throws -> ReviewExecutionResult
    ) {
        self.run = run
    }
}

extension ReviewExecutionClient: DependencyKey {
    public static let liveValue = Self { _ in
        ReviewExecutionResult()
    }
}

extension ReviewExecutionClient: TestDependencyKey {
    public static let testValue = Self(
        run: unimplemented("\(Self.self).run", placeholder: ReviewExecutionResult())
    )
}

public extension DependencyValues {
    var reviewExecutionClient: ReviewExecutionClient {
        get { self[ReviewExecutionClient.self] }
        set { self[ReviewExecutionClient.self] = newValue }
    }
}
