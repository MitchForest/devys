import Foundation
import ServerProtocol

struct PersistedPairing: Codable, Sendable {
    let pairing: PairingRecord
    let authToken: String
}

struct PairingStore: Sendable {
    private let fileURL: URL

    init(baseDirectoryURL: URL? = nil) throws {
        let root = try baseDirectoryURL ?? SessionStore.defaultDataRootURL()
        fileURL = root.appendingPathComponent("pairings.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func loadAll() throws -> [PersistedPairing] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try ServerJSONCoding.makeDecoder().decode([PersistedPairing].self, from: data)
    }

    func save(_ pairings: [PersistedPairing]) throws {
        let data = try ServerJSONCoding.makeEncoder().encode(pairings)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct CommandProfileStore: Sendable {
    private let fileURL: URL

    init(baseDirectoryURL: URL? = nil) throws {
        let root = try baseDirectoryURL ?? SessionStore.defaultDataRootURL()
        fileURL = root.appendingPathComponent("profiles.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func loadAll() throws -> [CommandProfile] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try ServerJSONCoding.makeDecoder().decode([CommandProfile].self, from: data)
    }

    func save(_ profiles: [CommandProfile]) throws {
        let data = try ServerJSONCoding.makeEncoder().encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct ServerIdentityStore: Sendable {
    private let fileURL: URL

    init(baseDirectoryURL: URL? = nil) throws {
        let root = try baseDirectoryURL ?? SessionStore.defaultDataRootURL()
        fileURL = root.appendingPathComponent("server-identity.txt", isDirectory: false)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func loadOrCreateFingerprint() throws -> String {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }

        let fingerprint = UUID().uuidString.lowercased()
        try Data(fingerprint.utf8).write(to: fileURL, options: .atomic)
        return fingerprint
    }
}

struct PairingChallenge: Sendable {
    let id: String
    let setupCode: String
    let expiresAt: Date
    let requestedDeviceName: String?
}

enum CommandProfileDefaults {
    static let shell = CommandProfile(
        id: "shell",
        label: "Shell",
        command: nil,
        arguments: [],
        environment: [:],
        requiredCapabilities: [.tmux],
        isDefault: true
    )

    static let claudeCode = CommandProfile(
        id: "cc",
        label: "Claude Code",
        command: "claude",
        arguments: ["code"],
        environment: [:],
        requiredCapabilities: [.tmux, .claude],
        isDefault: true
    )

    static let codex = CommandProfile(
        id: "cx",
        label: "Codex",
        command: "codex",
        arguments: [],
        environment: [:],
        requiredCapabilities: [.tmux, .codex],
        isDefault: true
    )

    static let all: [CommandProfile] = [shell, claudeCode, codex]
}

extension CommandProfile {
    var normalizedForStorage: CommandProfile {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandProfile(
            id: trimmedID,
            label: trimmedLabel.isEmpty ? trimmedID : trimmedLabel,
            command: trimmedCommand?.isEmpty == true ? nil : trimmedCommand,
            arguments: arguments,
            environment: environment,
            requiredCapabilities: requiredCapabilities,
            isDefault: isDefault
        )
    }
}
