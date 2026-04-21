// RepositorySettings.swift
// DevysCore - Repository-scoped settings.

import Foundation

public struct RepositorySettings: Codable, Equatable, Sendable {
    public var workspaceCreation: WorkspaceCreationDefaults
    public var claudeLauncher: LauncherTemplate
    public var codexLauncher: LauncherTemplate
    public var review: ReviewSettings
    public var startupProfiles: [StartupProfile]
    public var defaultStartupProfileID: StartupProfile.ID?
    public var portLabels: [RepositoryPortLabel]

    private enum CodingKeys: String, CodingKey {
        case workspaceCreation
        case claudeLauncher
        case codexLauncher
        case review
        case startupProfiles
        case defaultStartupProfileID
        case portLabels
    }

    public init(
        workspaceCreation: WorkspaceCreationDefaults = WorkspaceCreationDefaults(),
        claudeLauncher: LauncherTemplate = .claudeDefault,
        codexLauncher: LauncherTemplate = .codexDefault,
        review: ReviewSettings = ReviewSettings(),
        startupProfiles: [StartupProfile] = [],
        defaultStartupProfileID: StartupProfile.ID? = nil,
        portLabels: [RepositoryPortLabel] = []
    ) {
        self.workspaceCreation = workspaceCreation
        self.claudeLauncher = claudeLauncher
        self.codexLauncher = codexLauncher
        self.review = review
        self.startupProfiles = startupProfiles
        self.defaultStartupProfileID = defaultStartupProfileID
        self.portLabels = portLabels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceCreation = try container.decodeIfPresent(
            WorkspaceCreationDefaults.self,
            forKey: .workspaceCreation
        ) ?? WorkspaceCreationDefaults()
        claudeLauncher = try container.decodeIfPresent(
            LauncherTemplate.self,
            forKey: .claudeLauncher
        ) ?? .claudeDefault
        codexLauncher = try container.decodeIfPresent(
            LauncherTemplate.self,
            forKey: .codexLauncher
        ) ?? .codexDefault
        review = try container.decodeIfPresent(
            ReviewSettings.self,
            forKey: .review
        ) ?? ReviewSettings()
        startupProfiles = try container.decodeIfPresent(
            [StartupProfile].self,
            forKey: .startupProfiles
        ) ?? []
        defaultStartupProfileID = try container.decodeIfPresent(
            StartupProfile.ID.self,
            forKey: .defaultStartupProfileID
        )
        portLabels = try container.decodeIfPresent(
            [RepositoryPortLabel].self,
            forKey: .portLabels
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaceCreation, forKey: .workspaceCreation)
        try container.encode(claudeLauncher, forKey: .claudeLauncher)
        try container.encode(codexLauncher, forKey: .codexLauncher)
        try container.encode(review, forKey: .review)
        try container.encode(startupProfiles, forKey: .startupProfiles)
        try container.encodeIfPresent(defaultStartupProfileID, forKey: .defaultStartupProfileID)
        try container.encode(portLabels, forKey: .portLabels)
    }
}

public struct ReviewSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var reviewOnCommit: Bool
    public var reviewOnPullRequestUpdates: Bool
    public var auditHarness: BuiltInLauncherKind
    public var followUpHarness: BuiltInLauncherKind
    public var auditModelOverride: String?
    public var followUpModelOverride: String?
    public var auditReasoningOverride: String?
    public var followUpReasoningOverride: String?
    public var auditDangerousPermissionsOverride: Bool?
    public var followUpDangerousPermissionsOverride: Bool?
    public var additionalInstructions: String?

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case reviewOnCommit
        case reviewOnPullRequestUpdates
        case auditHarness
        case followUpHarness
        case auditModelOverride
        case followUpModelOverride
        case auditReasoningOverride
        case followUpReasoningOverride
        case auditDangerousPermissionsOverride
        case followUpDangerousPermissionsOverride
        case additionalInstructions
    }

    public init(
        isEnabled: Bool = true,
        reviewOnCommit: Bool = false,
        reviewOnPullRequestUpdates: Bool = false,
        auditHarness: BuiltInLauncherKind = .codex,
        followUpHarness: BuiltInLauncherKind = .codex,
        auditModelOverride: String? = nil,
        followUpModelOverride: String? = nil,
        auditReasoningOverride: String? = nil,
        followUpReasoningOverride: String? = nil,
        auditDangerousPermissionsOverride: Bool? = nil,
        followUpDangerousPermissionsOverride: Bool? = nil,
        additionalInstructions: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.reviewOnCommit = reviewOnCommit
        self.reviewOnPullRequestUpdates = reviewOnPullRequestUpdates
        self.auditHarness = auditHarness
        self.followUpHarness = followUpHarness
        self.auditModelOverride = auditModelOverride
        self.followUpModelOverride = followUpModelOverride
        self.auditReasoningOverride = auditReasoningOverride
        self.followUpReasoningOverride = followUpReasoningOverride
        self.auditDangerousPermissionsOverride = auditDangerousPermissionsOverride
        self.followUpDangerousPermissionsOverride = followUpDangerousPermissionsOverride
        self.additionalInstructions = additionalInstructions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        reviewOnCommit = try container.decodeIfPresent(Bool.self, forKey: .reviewOnCommit) ?? false
        reviewOnPullRequestUpdates = try container.decodeIfPresent(
            Bool.self,
            forKey: .reviewOnPullRequestUpdates
        ) ?? false
        auditHarness = try container.decodeIfPresent(
            BuiltInLauncherKind.self,
            forKey: .auditHarness
        ) ?? .codex
        followUpHarness = try container.decodeIfPresent(
            BuiltInLauncherKind.self,
            forKey: .followUpHarness
        ) ?? .codex
        auditModelOverride = try container.decodeIfPresent(
            String.self,
            forKey: .auditModelOverride
        )
        followUpModelOverride = try container.decodeIfPresent(
            String.self,
            forKey: .followUpModelOverride
        )
        auditReasoningOverride = try container.decodeIfPresent(
            String.self,
            forKey: .auditReasoningOverride
        )
        followUpReasoningOverride = try container.decodeIfPresent(
            String.self,
            forKey: .followUpReasoningOverride
        )
        auditDangerousPermissionsOverride = try container.decodeIfPresent(
            Bool.self,
            forKey: .auditDangerousPermissionsOverride
        )
        followUpDangerousPermissionsOverride = try container.decodeIfPresent(
            Bool.self,
            forKey: .followUpDangerousPermissionsOverride
        )
        additionalInstructions = try container.decodeIfPresent(
            String.self,
            forKey: .additionalInstructions
        )
    }
}

public struct RepositoryPortLabel: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var port: Int
    public var label: String
    public var scheme: String
    public var path: String

    public init(
        id: ID = UUID(),
        port: Int,
        label: String,
        scheme: String = "http",
        path: String = ""
    ) {
        self.id = id
        self.port = port
        self.label = label
        self.scheme = scheme
        self.path = path
    }
}

public struct WorkspaceCreationDefaults: Codable, Equatable, Sendable {
    public var defaultBaseBranch: String
    public var copyIgnoredFiles: Bool
    public var copyUntrackedFiles: Bool

    public init(
        defaultBaseBranch: String = "main",
        copyIgnoredFiles: Bool = false,
        copyUntrackedFiles: Bool = false
    ) {
        self.defaultBaseBranch = defaultBaseBranch
        self.copyIgnoredFiles = copyIgnoredFiles
        self.copyUntrackedFiles = copyUntrackedFiles
    }
}

public struct LauncherTemplate: Codable, Equatable, Sendable {
    public var executable: String
    public var model: String?
    public var reasoningLevel: String?
    public var dangerousPermissions: Bool
    public var extraArguments: [String]
    public var executionBehavior: LauncherExecutionBehavior

    public init(
        executable: String,
        model: String? = nil,
        reasoningLevel: String? = nil,
        dangerousPermissions: Bool = false,
        extraArguments: [String] = [],
        executionBehavior: LauncherExecutionBehavior = .runImmediately
    ) {
        self.executable = executable
        self.model = model
        self.reasoningLevel = reasoningLevel
        self.dangerousPermissions = dangerousPermissions
        self.extraArguments = extraArguments
        self.executionBehavior = executionBehavior
    }

    public static let claudeDefault = LauncherTemplate(
        executable: "claude",
        dangerousPermissions: true
    )
    public static let codexDefault = LauncherTemplate(executable: "codex")
}

public enum LauncherExecutionBehavior: String, Codable, CaseIterable, Sendable {
    case runImmediately
    case stageInTerminal
}

public struct StartupProfile: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var displayName: String
    public var description: String
    public var steps: [StartupProfileStep]

    public init(
        id: ID = UUID(),
        displayName: String,
        description: String = "",
        steps: [StartupProfileStep] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.steps = steps
    }
}

public struct StartupProfileStep: Identifiable, Codable, Equatable, Sendable {
    public typealias ID = UUID

    public var id: ID
    public var displayName: String
    public var workingDirectory: String
    public var command: String
    public var environment: [String: String]
    public var launchMode: StartupProfileLaunchMode

    public init(
        id: ID = UUID(),
        displayName: String,
        workingDirectory: String = "",
        command: String,
        environment: [String: String] = [:],
        launchMode: StartupProfileLaunchMode = .newTab
    ) {
        self.id = id
        self.displayName = displayName
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
        self.launchMode = launchMode
    }
}

public enum StartupProfileLaunchMode: String, Codable, CaseIterable, Sendable {
    case newTab
    case split
    case backgroundManagedProcess
}
