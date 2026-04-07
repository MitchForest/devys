// RepositorySettings.swift
// DevysCore - Repository-scoped settings.

import Foundation

public struct RepositorySettings: Codable, Equatable, Sendable {
    public var workspaceCreation: WorkspaceCreationDefaults
    public var claudeLauncher: LauncherTemplate
    public var codexLauncher: LauncherTemplate
    public var startupProfiles: [StartupProfile]
    public var defaultStartupProfileID: StartupProfile.ID?
    public var portLabels: [RepositoryPortLabel]

    public init(
        workspaceCreation: WorkspaceCreationDefaults = WorkspaceCreationDefaults(),
        claudeLauncher: LauncherTemplate = .claudeDefault,
        codexLauncher: LauncherTemplate = .codexDefault,
        startupProfiles: [StartupProfile] = [],
        defaultStartupProfileID: StartupProfile.ID? = nil,
        portLabels: [RepositoryPortLabel] = []
    ) {
        self.workspaceCreation = workspaceCreation
        self.claudeLauncher = claudeLauncher
        self.codexLauncher = codexLauncher
        self.startupProfiles = startupProfiles
        self.defaultStartupProfileID = defaultStartupProfileID
        self.portLabels = portLabels
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

    public static let claudeDefault = LauncherTemplate(executable: "claude")
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
