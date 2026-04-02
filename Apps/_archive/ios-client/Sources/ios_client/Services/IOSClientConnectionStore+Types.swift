import Foundation
import ServerProtocol

extension IOSClientConnectionStore {
    struct CommandProfileDraft: Equatable, Identifiable {
        var sourceProfileID: String?
        var id: String
        var label: String
        var command: String
        var argumentsText: String
        var environmentText: String
        var requiresTmux: Bool
        var requiresClaude: Bool
        var requiresCodex: Bool
        var isDefault: Bool
        var setAsStartupDefault: Bool

        var isEditingExisting: Bool { sourceProfileID != nil }

        init() {
            sourceProfileID = nil
            id = ""
            label = ""
            command = ""
            argumentsText = ""
            environmentText = ""
            requiresTmux = true
            requiresClaude = false
            requiresCodex = false
            isDefault = false
            setAsStartupDefault = true
        }

        init(profile: CommandProfile, selectedCommandProfileID: String) {
            sourceProfileID = profile.id
            id = profile.id
            label = profile.label
            command = profile.command ?? ""
            argumentsText = profile.arguments.joined(separator: "\n")
            environmentText = profile.environment
                .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\n")
            requiresTmux = profile.requiredCapabilities.contains(.tmux)
            requiresClaude = profile.requiredCapabilities.contains(.claude)
            requiresCodex = profile.requiredCapabilities.contains(.codex)
            isDefault = profile.isDefault
            setAsStartupDefault = selectedCommandProfileID == profile.id
        }

        func toProfile() throws -> CommandProfile {
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedID.isEmpty else {
                throw CommandProfileDraftError(message: "Profile id is required.")
            }
            guard normalizedID.range(of: "^[a-z0-9_-]{1,32}$", options: .regularExpression) != nil else {
                throw CommandProfileDraftError(message: "Profile id must match ^[a-z0-9_-]{1,32}$.")
            }
            guard !normalizedLabel.isEmpty else {
                throw CommandProfileDraftError(message: "Profile label is required.")
            }
            if normalizedCommand.contains("\n") {
                throw CommandProfileDraftError(message: "Command must be single-line.")
            }

            let arguments = parseArguments(argumentsText)
            let environment = try parseEnvironment(environmentText)
            let requiredCapabilities = selectedCapabilities()

            return CommandProfile(
                id: normalizedID,
                label: normalizedLabel,
                command: normalizedCommand.isEmpty ? nil : normalizedCommand,
                arguments: arguments,
                environment: environment,
                requiredCapabilities: requiredCapabilities,
                isDefault: isDefault
            )
        }

        private func parseArguments(_ text: String) -> [String] {
            text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        private func parseEnvironment(_ text: String) throws -> [String: String] {
            var environment: [String: String] = [:]
            let lines = text.split(whereSeparator: \.isNewline)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                guard let separatorIndex = line.firstIndex(of: "=") else {
                    throw CommandProfileDraftError(message: "Environment lines must be KEY=VALUE.")
                }
                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let valueIndex = line.index(after: separatorIndex)
                let value = String(line[valueIndex...])
                guard !key.isEmpty else {
                    throw CommandProfileDraftError(message: "Environment keys must not be empty.")
                }
                environment[key] = value
            }
            return environment
        }

        private func selectedCapabilities() -> [CommandProfileCapability] {
            var capabilities: [CommandProfileCapability] = []
            if requiresTmux {
                capabilities.append(.tmux)
            }
            if requiresClaude {
                capabilities.append(.claude)
            }
            if requiresCodex {
                capabilities.append(.codex)
            }
            return capabilities
        }
    }

    struct CommandProfileDraftError: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    struct ReadinessTelemetrySnapshot: Equatable {
        var connectionAttempts = 0
        var connectionSuccesses = 0
        var connectionFailures = 0
        var lastTimeToConnectedMs: Int?
        var terminalLaunchAttempts = 0
        var terminalLaunchSuccesses = 0
        var terminalLaunchFailures = 0
        var lastTimeToPromptMs: Int?
        var reconnectAttempts = 0
        var reconnectSuccesses = 0
        var reconnectFailures = 0
        var lastReconnectLatencyMs: Int?
        var profileLaunchAttempts = 0
        var profileLaunchSuccesses = 0
        var profileLaunchFailures = 0
        var lastProfileLaunchProfileID: String?
        var lastProfileLaunchError: String?
        var lastUpdatedAt: Date?

        var profileLaunchSuccessRatePercent: Int? {
            guard profileLaunchAttempts > 0 else { return nil }
            let ratio = Double(profileLaunchSuccesses) / Double(profileLaunchAttempts)
            return Int((ratio * 100.0).rounded())
        }
    }

    enum SetupStep: Int, CaseIterable, Identifiable {
        case pair
        case trust
        case validation
        case defaults
        case done

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .pair:
                return "Pair"
            case .trust:
                return "Trust"
            case .validation:
                return "Validate"
            case .defaults:
                return "Defaults"
            case .done:
                return "Done"
            }
        }
    }

    struct SetupPreflightCheck: Equatable, Identifiable {
        let id: String
        let label: String
        let passed: Bool
        let isRequired: Bool
        let detail: String
    }

    struct SSHProfileDraft: Equatable {
        var profileID: String?
        var name: String
        var host: String
        var portText: String
        var username: String
        var authKind: SSHAuthMethodKind
        var password: String
        var privateKey: String
        var passphrase: String
        var notes: String

        init(profile: SSHConnectionProfile? = nil) {
            profileID = profile?.id
            name = profile?.name ?? ""
            host = profile?.host ?? ""
            portText = String(profile?.port ?? 22)
            username = profile?.username ?? ""
            authKind = profile?.auth.kind ?? .password
            password = ""
            privateKey = ""
            passphrase = ""
            notes = profile?.notes ?? ""
        }

        var normalizedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var normalizedHost: String {
            host.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var normalizedUsername: String {
            username.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var normalizedNotes: String? {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var parsedPort: Int? {
            Int(portText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    struct SSHHostTrustPrompt: Equatable, Identifiable {
        let id = UUID()
        let host: String
        let port: Int
        let algorithm: String
        let fingerprint: String
    }

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    enum TerminalLaunchMode: String, CaseIterable, Identifiable {
        case newSession
        case attachExisting

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newSession:
                return "New"
            case .attachExisting:
                return "Attach"
            }
        }
    }

    enum TerminalSpecialKey: String, CaseIterable, Identifiable {
        case escape
        case tab
        case up
        case down
        case left
        case right
        case pageUp
        case pageDown
        case home
        case end
        case enter
        case backspace
        case interrupt

        var id: String { rawValue }
    }

    struct ResumeSnapshot: Codable {
        let serverURL: String
        let workspacePath: String
        let sessionID: String?
        let terminalID: String
        let cols: Int
        let rows: Int
        let cursor: UInt64?
        let commandProfileID: String?
        let launchMode: String?

        enum CodingKeys: String, CodingKey {
            case serverURL
            case workspacePath
            case sessionID
            case terminalID
            case cols
            case rows
            case cursor
            case commandProfileID = "commandProfileId"
            case launchPreset
            case launchMode
        }

        init(
            serverURL: String,
            workspacePath: String,
            sessionID: String?,
            terminalID: String,
            cols: Int,
            rows: Int,
            cursor: UInt64?,
            commandProfileID: String?,
            launchMode: String?
        ) {
            self.serverURL = serverURL
            self.workspacePath = workspacePath
            self.sessionID = sessionID
            self.terminalID = terminalID
            self.cols = cols
            self.rows = rows
            self.cursor = cursor
            self.commandProfileID = commandProfileID
            self.launchMode = launchMode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            serverURL = try container.decode(String.self, forKey: .serverURL)
            workspacePath = try container.decode(String.self, forKey: .workspacePath)
            sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
            terminalID = try container.decode(String.self, forKey: .terminalID)
            cols = try container.decode(Int.self, forKey: .cols)
            rows = try container.decode(Int.self, forKey: .rows)
            cursor = try container.decodeIfPresent(UInt64.self, forKey: .cursor)
            commandProfileID = try container.decodeIfPresent(String.self, forKey: .commandProfileID)
                ?? container.decodeIfPresent(String.self, forKey: .launchPreset)
            launchMode = try container.decodeIfPresent(String.self, forKey: .launchMode)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(serverURL, forKey: .serverURL)
            try container.encode(workspacePath, forKey: .workspacePath)
            try container.encodeIfPresent(sessionID, forKey: .sessionID)
            try container.encode(terminalID, forKey: .terminalID)
            try container.encode(cols, forKey: .cols)
            try container.encode(rows, forKey: .rows)
            try container.encodeIfPresent(cursor, forKey: .cursor)
            try container.encodeIfPresent(commandProfileID, forKey: .commandProfileID)
            try container.encodeIfPresent(launchMode, forKey: .launchMode)
        }
    }

    enum Keys {
        static let serverURL = "ios_client.server_url"
        static let workspacePath = "ios_client.workspace_path"
        static let commandProfileID = "ios_client.command_profile_id"
        static let launchMode = "ios_client.launch_mode"
        static let selectedSessionID = "ios_client.selected_session_id"
        static let resumeSnapshot = "ios_client.resume_snapshot"
        static let setupCompleted = "ios_client.setup_completed"
        static let setupAutoConnect = "ios_client.setup_auto_connect"
        static let setupAutoResume = "ios_client.setup_auto_resume"
        static let trustedFingerprints = "ios_client.trusted_server_fingerprints"
    }

    static let fallbackCommandProfiles: [CommandProfile] = [
        CommandProfile(
            id: "shell",
            label: "Shell",
            command: nil,
            arguments: [],
            environment: [:],
            requiredCapabilities: [.tmux],
            isDefault: true
        ),
        CommandProfile(
            id: "cc",
            label: "Claude Code",
            command: "claude",
            arguments: ["code"],
            environment: [:],
            requiredCapabilities: [.tmux, .claude],
            isDefault: true
        ),
        CommandProfile(
            id: "cx",
            label: "Codex",
            command: "codex",
            arguments: [],
            environment: [:],
            requiredCapabilities: [.tmux, .codex],
            isDefault: true
        )
    ]
}
