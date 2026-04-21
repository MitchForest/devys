import Foundation
import Workspace

public enum ReviewTargetKind: String, Codable, CaseIterable, Sendable {
    case unstagedChanges
    case stagedChanges
    case lastCommit
    case currentBranch
    case commitRange
    case pullRequest
    case selection
}

public struct ReviewTarget: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: ReviewTargetKind
    public var workspaceID: Workspace.ID?
    public var repositoryRootURL: URL
    public var title: String
    public var branchName: String?
    public var baseBranchName: String?
    public var commitShas: [String]
    public var pullRequestNumber: Int?
    public var selectedPaths: [String]

    public init(
        id: String,
        kind: ReviewTargetKind,
        workspaceID: Workspace.ID? = nil,
        repositoryRootURL: URL,
        title: String,
        branchName: String? = nil,
        baseBranchName: String? = nil,
        commitShas: [String] = [],
        pullRequestNumber: Int? = nil,
        selectedPaths: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.workspaceID = workspaceID
        self.repositoryRootURL = repositoryRootURL
        self.title = title
        self.branchName = branchName
        self.baseBranchName = baseBranchName
        self.commitShas = commitShas
        self.pullRequestNumber = pullRequestNumber
        self.selectedPaths = selectedPaths
    }

    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.displayTitle : title
    }
}

public enum ReviewTriggerSource: String, Codable, CaseIterable, Sendable {
    case manual
    case postCommitHook
    case pullRequestCommand
    case pullRequestHook
    case workspaceOpen
    case scheduled
    case remoteHost
}

public struct ReviewTrigger: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var source: ReviewTriggerSource
    public var createdAt: Date
    public var isUserVisible: Bool

    public init(
        id: UUID = UUID(),
        source: ReviewTriggerSource,
        createdAt: Date = Date(),
        isUserVisible: Bool = true
    ) {
        self.id = id
        self.source = source
        self.createdAt = createdAt
        self.isUserVisible = isUserVisible
    }
}

public enum ReviewRunnerLocation: String, Codable, CaseIterable, Sendable {
    case localHost
    case remoteHost
    case macMini
}

public struct ReviewProfile: Codable, Equatable, Sendable {
    public var auditHarness: BuiltInLauncherKind
    public var followUpHarness: BuiltInLauncherKind
    public var auditModelOverride: String?
    public var followUpModelOverride: String?
    public var auditReasoningOverride: String?
    public var followUpReasoningOverride: String?
    public var auditDangerousPermissionsOverride: Bool?
    public var followUpDangerousPermissionsOverride: Bool?
    public var additionalInstructions: String?
    public var runnerLocation: ReviewRunnerLocation

    public init(
        auditHarness: BuiltInLauncherKind = .codex,
        followUpHarness: BuiltInLauncherKind = .codex,
        auditModelOverride: String? = nil,
        followUpModelOverride: String? = nil,
        auditReasoningOverride: String? = nil,
        followUpReasoningOverride: String? = nil,
        auditDangerousPermissionsOverride: Bool? = nil,
        followUpDangerousPermissionsOverride: Bool? = nil,
        additionalInstructions: String? = nil,
        runnerLocation: ReviewRunnerLocation = .localHost
    ) {
        self.auditHarness = auditHarness
        self.followUpHarness = followUpHarness
        self.auditModelOverride = auditModelOverride
        self.followUpModelOverride = followUpModelOverride
        self.auditReasoningOverride = auditReasoningOverride
        self.followUpReasoningOverride = followUpReasoningOverride
        self.auditDangerousPermissionsOverride = auditDangerousPermissionsOverride
        self.followUpDangerousPermissionsOverride = followUpDangerousPermissionsOverride
        self.additionalInstructions = additionalInstructions
        self.runnerLocation = runnerLocation
    }

    public init(settings: ReviewSettings, runnerLocation: ReviewRunnerLocation = .localHost) {
        self.init(
            auditHarness: settings.auditHarness,
            followUpHarness: settings.followUpHarness,
            auditModelOverride: settings.auditModelOverride,
            followUpModelOverride: settings.followUpModelOverride,
            auditReasoningOverride: settings.auditReasoningOverride,
            followUpReasoningOverride: settings.followUpReasoningOverride,
            auditDangerousPermissionsOverride: settings.auditDangerousPermissionsOverride,
            followUpDangerousPermissionsOverride: settings.followUpDangerousPermissionsOverride,
            additionalInstructions: settings.additionalInstructions,
            runnerLocation: runnerLocation
        )
    }
}

public enum ReviewRunStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case preparing
    case running
    case completed
    case failed
    case cancelled

    public var isActive: Bool {
        switch self {
        case .queued, .preparing, .running:
            true
        case .completed, .failed, .cancelled:
            false
        }
    }
}

public enum ReviewOverallRisk: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public struct ReviewIssueCounts: Codable, Equatable, Sendable {
    public var total: Int
    public var open: Int
    public var dismissed: Int
    public var acceptedRisk: Int
    public var resolved: Int
    public var critical: Int
    public var major: Int
    public var minor: Int

    public init(
        total: Int = 0,
        open: Int = 0,
        dismissed: Int = 0,
        acceptedRisk: Int = 0,
        resolved: Int = 0,
        critical: Int = 0,
        major: Int = 0,
        minor: Int = 0
    ) {
        self.total = total
        self.open = open
        self.dismissed = dismissed
        self.acceptedRisk = acceptedRisk
        self.resolved = resolved
        self.critical = critical
        self.major = major
        self.minor = minor
    }
}

public struct ReviewArtifactSet: Codable, Equatable, Sendable {
    public var inputSnapshotPath: String?
    public var auditPromptPath: String?
    public var rawStdoutPath: String?
    public var rawStderrPath: String?
    public var parsedResultPath: String?
    public var renderedSummaryPath: String?

    public init(
        inputSnapshotPath: String? = nil,
        auditPromptPath: String? = nil,
        rawStdoutPath: String? = nil,
        rawStderrPath: String? = nil,
        parsedResultPath: String? = nil,
        renderedSummaryPath: String? = nil
    ) {
        self.inputSnapshotPath = inputSnapshotPath
        self.auditPromptPath = auditPromptPath
        self.rawStdoutPath = rawStdoutPath
        self.rawStderrPath = rawStderrPath
        self.parsedResultPath = parsedResultPath
        self.renderedSummaryPath = renderedSummaryPath
    }
}

public struct ReviewRun: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var target: ReviewTarget
    public var trigger: ReviewTrigger
    public var profile: ReviewProfile
    public var status: ReviewRunStatus
    public var artifactSet: ReviewArtifactSet
    public var overallRisk: ReviewOverallRisk?
    public var issueCounts: ReviewIssueCounts
    public var issueIDs: [UUID]
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var lastErrorMessage: String?

    public init(
        id: UUID = UUID(),
        target: ReviewTarget,
        trigger: ReviewTrigger,
        profile: ReviewProfile,
        status: ReviewRunStatus = .queued,
        artifactSet: ReviewArtifactSet = ReviewArtifactSet(),
        overallRisk: ReviewOverallRisk? = nil,
        issueCounts: ReviewIssueCounts = ReviewIssueCounts(),
        issueIDs: [UUID] = [],
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.target = target
        self.trigger = trigger
        self.profile = profile
        self.status = status
        self.artifactSet = artifactSet
        self.overallRisk = overallRisk
        self.issueCounts = issueCounts
        self.issueIDs = issueIDs
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastErrorMessage = lastErrorMessage
    }

    public var displayStatus: String {
        switch status {
        case .queued:
            "Queued"
        case .preparing:
            "Preparing"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    public static func sort(
        _ lhs: ReviewRun,
        _ rhs: ReviewRun
    ) -> Bool {
        if lhs.status.isActive != rhs.status.isActive {
            return lhs.status.isActive && !rhs.status.isActive
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum ReviewIssueSeverity: String, Codable, CaseIterable, Sendable {
    case minor
    case major
    case critical
}

public enum ReviewIssueConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum ReviewIssueStatus: String, Codable, CaseIterable, Sendable {
    case open
    case dismissed
    case acceptedRisk
    case followUpPrepared
    case resolved
}

public struct ReviewIssueLocation: Codable, Equatable, Sendable {
    public var path: String
    public var line: Int?
    public var column: Int?

    public init(
        path: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.path = path
        self.line = line
        self.column = column
    }
}

public struct ReviewIssue: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var severity: ReviewIssueSeverity
    public var confidence: ReviewIssueConfidence
    public var title: String
    public var summary: String
    public var rationale: String
    public var paths: [String]
    public var locations: [ReviewIssueLocation]
    public var sourceReferences: [String]
    public var dedupeKey: String
    public var status: ReviewIssueStatus
    public var followUpPromptArtifactPath: String?

    public init(
        id: UUID = UUID(),
        runID: UUID,
        severity: ReviewIssueSeverity,
        confidence: ReviewIssueConfidence,
        title: String,
        summary: String,
        rationale: String,
        paths: [String] = [],
        locations: [ReviewIssueLocation] = [],
        sourceReferences: [String] = [],
        dedupeKey: String,
        status: ReviewIssueStatus = .open,
        followUpPromptArtifactPath: String? = nil
    ) {
        self.id = id
        self.runID = runID
        self.severity = severity
        self.confidence = confidence
        self.title = title
        self.summary = summary
        self.rationale = rationale
        self.paths = paths
        self.locations = locations
        self.sourceReferences = sourceReferences
        self.dedupeKey = dedupeKey
        self.status = status
        self.followUpPromptArtifactPath = followUpPromptArtifactPath
    }
}

public struct ReviewFixDraft: Codable, Equatable, Sendable {
    public var issueID: UUID
    public var harness: BuiltInLauncherKind
    public var resolvedCommandPreview: String
    public var promptArtifactPath: String
    public var opensInTerminal: Bool

    public init(
        issueID: UUID,
        harness: BuiltInLauncherKind,
        resolvedCommandPreview: String,
        promptArtifactPath: String,
        opensInTerminal: Bool = true
    ) {
        self.issueID = issueID
        self.harness = harness
        self.resolvedCommandPreview = resolvedCommandPreview
        self.promptArtifactPath = promptArtifactPath
        self.opensInTerminal = opensInTerminal
    }
}

public struct ReviewWorkspaceSnapshot: Codable, Equatable, Sendable {
    public var runs: [ReviewRun]
    public var issues: [ReviewIssue]

    public init(
        runs: [ReviewRun] = [],
        issues: [ReviewIssue] = []
    ) {
        self.runs = runs
        self.issues = issues
    }
}

public extension ReviewTargetKind {
    static var manualEntryTargets: [Self] {
        [
            .unstagedChanges,
            .stagedChanges,
            .lastCommit,
            .currentBranch
        ]
    }

    var displayTitle: String {
        switch self {
        case .unstagedChanges:
            "Unstaged Changes"
        case .stagedChanges:
            "Staged Changes"
        case .lastCommit:
            "Last Commit"
        case .currentBranch:
            "Current Branch"
        case .commitRange:
            "Commit Range"
        case .pullRequest:
            "Pull Request"
        case .selection:
            "Selection"
        }
    }

    var pickerSubtitle: String {
        switch self {
        case .unstagedChanges:
            "Audit local edits that have not been staged yet."
        case .stagedChanges:
            "Audit the staged diff that is ready to commit."
        case .lastCommit:
            "Audit the most recent local commit."
        case .currentBranch:
            "Audit the current branch diff against its base."
        case .commitRange:
            "Audit a specific range of commits."
        case .pullRequest:
            "Audit the open pull request mapped to this workspace."
        case .selection:
            "Audit a focused selection of files or hunks."
        }
    }
}
