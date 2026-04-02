import Foundation

public enum CommandProfileCapability: String, Codable, Sendable, CaseIterable {
    case tmux
    case claude
    case codex
}

public struct CommandProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let command: String?
    public let arguments: [String]
    public let environment: [String: String]
    public let requiredCapabilities: [CommandProfileCapability]
    public let isDefault: Bool

    public init(
        id: String,
        label: String,
        command: String? = nil,
        arguments: [String] = [],
        environment: [String: String] = [:],
        requiredCapabilities: [CommandProfileCapability] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.label = label
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.requiredCapabilities = requiredCapabilities
        self.isDefault = isDefault
    }
}

public struct ListCommandProfilesResponse: Codable, Sendable, Equatable {
    public let profiles: [CommandProfile]

    public init(profiles: [CommandProfile]) {
        self.profiles = profiles
    }
}

public struct SaveCommandProfileRequest: Codable, Sendable, Equatable {
    public let profile: CommandProfile

    public init(profile: CommandProfile) {
        self.profile = profile
    }
}

public struct SaveCommandProfileResponse: Codable, Sendable, Equatable {
    public let profile: CommandProfile

    public init(profile: CommandProfile) {
        self.profile = profile
    }
}

public struct DeleteCommandProfileRequest: Codable, Sendable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct DeleteCommandProfileResponse: Codable, Sendable, Equatable {
    public let deletedID: String

    enum CodingKeys: String, CodingKey {
        case deletedID = "deletedId"
    }

    public init(deletedID: String) {
        self.deletedID = deletedID
    }
}

public struct ValidateCommandProfileRequest: Codable, Sendable, Equatable {
    public let profile: CommandProfile

    public init(profile: CommandProfile) {
        self.profile = profile
    }
}

public struct ValidateCommandProfileResponse: Codable, Sendable, Equatable {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}
