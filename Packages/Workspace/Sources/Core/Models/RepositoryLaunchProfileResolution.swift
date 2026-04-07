// RepositoryLaunchProfileResolution.swift
// DevysCore - Repository launch profile planning and command resolution.

import Foundation

public enum BuiltInLauncherKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
}

public struct ResolvedLauncherCommand: Equatable, Sendable {
    public var command: String
    public var executionBehavior: LauncherExecutionBehavior

    public init(command: String, executionBehavior: LauncherExecutionBehavior) {
        self.command = command
        self.executionBehavior = executionBehavior
    }
}

public struct ResolvedStartupProfile: Equatable, Sendable {
    public var profile: StartupProfile
    public var steps: [ResolvedStartupProfileStep]

    public init(profile: StartupProfile, steps: [ResolvedStartupProfileStep]) {
        self.profile = profile
        self.steps = steps
    }
}

public struct ResolvedStartupProfileStep: Equatable, Sendable, Identifiable {
    public let id: StartupProfileStep.ID
    public var displayName: String
    public var workingDirectory: URL
    public var command: String
    public var environment: [String: String]
    public var launchMode: StartupProfileLaunchMode

    public init(
        id: StartupProfileStep.ID,
        displayName: String,
        workingDirectory: URL,
        command: String,
        environment: [String: String],
        launchMode: StartupProfileLaunchMode
    ) {
        self.id = id
        self.displayName = displayName
        self.workingDirectory = workingDirectory
        self.command = command
        self.environment = environment
        self.launchMode = launchMode
    }

    public var shellCommand: String {
        let environmentAssignments = environment
            .sorted { $0.key < $1.key }
            .map { "\(shellEscapedAssignmentKey($0.key))=\(shellEscapedArgument($0.value))" }
        let parts = environmentAssignments + [command]
        return parts.joined(separator: " ")
    }
}

public enum RepositoryLaunchResolutionError: LocalizedError, Equatable, Sendable {
    case emptyLauncherExecutable
    case startupProfileNotFound
    case stepCommandMissing(stepName: String)

    public var errorDescription: String? {
        switch self {
        case .emptyLauncherExecutable:
            return "Launcher executable must not be empty."
        case .startupProfileNotFound:
            return "The selected startup profile could not be found."
        case .stepCommandMissing(let stepName):
            return "\(stepName) is missing its command."
        }
    }
}

public enum RepositoryLaunchPlanner {
    public static func resolveLauncher(
        _ launcher: LauncherTemplate,
        kind: BuiltInLauncherKind
    ) throws -> ResolvedLauncherCommand {
        let executable = normalizedLauncherExecutable(
            launcher.executable.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind
        )
        guard !executable.isEmpty else {
            throw RepositoryLaunchResolutionError.emptyLauncherExecutable
        }

        var arguments: [String] = []

        switch kind {
        case .claude:
            if let model = normalizedOptionalString(launcher.model) {
                arguments.append(contentsOf: ["--model", model])
            }
            if let reasoningLevel = normalizedOptionalString(launcher.reasoningLevel) {
                arguments.append(contentsOf: ["--effort", reasoningLevel])
            }
            if launcher.dangerousPermissions {
                arguments.append("--dangerously-skip-permissions")
            }
        case .codex:
            if let model = normalizedOptionalString(launcher.model) {
                arguments.append(contentsOf: ["-m", model])
            }
            if let reasoningLevel = normalizedOptionalString(launcher.reasoningLevel) {
                arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(reasoningLevel)\""])
            }
            if launcher.dangerousPermissions {
                arguments.append("--dangerously-bypass-approvals-and-sandbox")
            }
        }

        arguments.append(
            contentsOf: launcher.extraArguments
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let command = ([executable] + arguments)
            .map(shellEscapedArgument)
            .joined(separator: " ")

        return ResolvedLauncherCommand(
            command: command,
            executionBehavior: launcher.executionBehavior
        )
    }

    public static func resolveDefaultStartupProfile(
        in settings: RepositorySettings,
        workspaceRoot: URL
    ) throws -> ResolvedStartupProfile {
        guard let defaultStartupProfileID = settings.defaultStartupProfileID else {
            throw RepositoryLaunchResolutionError.startupProfileNotFound
        }
        return try resolveStartupProfile(
            id: defaultStartupProfileID,
            in: settings,
            workspaceRoot: workspaceRoot
        )
    }

    public static func resolveStartupProfile(
        id: StartupProfile.ID,
        in settings: RepositorySettings,
        workspaceRoot: URL
    ) throws -> ResolvedStartupProfile {
        guard let profile = settings.startupProfiles.first(where: { $0.id == id }) else {
            throw RepositoryLaunchResolutionError.startupProfileNotFound
        }

        let resolvedSteps = try profile.steps.map { step in
            let trimmedCommand = step.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCommand.isEmpty else {
                throw RepositoryLaunchResolutionError.stepCommandMissing(stepName: step.displayName)
            }

            return ResolvedStartupProfileStep(
                id: step.id,
                displayName: step.displayName,
                workingDirectory: resolveWorkingDirectory(
                    step.workingDirectory,
                    workspaceRoot: workspaceRoot
                ),
                command: trimmedCommand,
                environment: normalizedEnvironment(step.environment),
                launchMode: step.launchMode
            )
        }

        return ResolvedStartupProfile(profile: profile, steps: resolvedSteps)
    }
}

private func normalizedLauncherExecutable(
    _ executable: String,
    kind: BuiltInLauncherKind
) -> String {
    switch (kind, executable.lowercased()) {
    case (.claude, "cc"):
        return "claude"
    case (.codex, "cx"):
        return "codex"
    default:
        return executable
    }
}

private func normalizedOptionalString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedEnvironment(_ environment: [String: String]) -> [String: String] {
    environment.reduce(into: [:]) { partialResult, pair in
        let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        partialResult[key] = value
    }
}

private func resolveWorkingDirectory(_ rawPath: String, workspaceRoot: URL) -> URL {
    let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty else {
        return workspaceRoot.standardizedFileURL
    }

    let baseURL: URL
    if trimmedPath.hasPrefix("/") {
        baseURL = URL(fileURLWithPath: trimmedPath)
    } else {
        baseURL = workspaceRoot.appendingPathComponent(trimmedPath, isDirectory: true)
    }

    return baseURL.standardizedFileURL
}

private func shellEscapedAssignmentKey(_ key: String) -> String {
    key.replacingOccurrences(of: " ", with: "_")
}

private func shellEscapedArgument(_ argument: String) -> String {
    guard argument.contains(where: \.isWhitespace) || argument.contains("'") else { return argument }
    return "'\(argument.replacingOccurrences(of: "'", with: "'\\''"))'"
}
