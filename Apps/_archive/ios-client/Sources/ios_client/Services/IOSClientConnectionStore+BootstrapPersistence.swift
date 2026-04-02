import Foundation
import ServerProtocol

extension IOSClientConnectionStore {
    static func loadPersistedState() -> PersistedState {
        let sharedConversationURL = UserDefaults.standard.string(forKey: ConversationConnectionDefaults.serverURLKey)
        return PersistedState(
            serverURL: UserDefaults.standard.string(forKey: Keys.serverURL) ?? sharedConversationURL ?? "",
            workspacePath: UserDefaults.standard.string(forKey: Keys.workspacePath) ?? "",
            commandProfileID: persistedOrLegacyCommandProfileID(),
            launchMode: TerminalLaunchMode(rawValue: UserDefaults.standard.string(forKey: Keys.launchMode) ?? "")
                ?? .newSession,
            selectedSessionID: UserDefaults.standard.string(forKey: Keys.selectedSessionID),
            setupCompleted: loadPersistedBool(forKey: Keys.setupCompleted, defaultValue: true),
            autoConnectOnLaunch: loadPersistedBool(forKey: Keys.setupAutoConnect, defaultValue: false),
            autoResumeLastSession: loadPersistedBool(forKey: Keys.setupAutoResume, defaultValue: true),
            trustedFingerprints: UserDefaults.standard.dictionary(forKey: Keys.trustedFingerprints)
                as? [String: String] ?? [:]
        )
    }

    static func loadPersistedBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func loadResumeSnapshot() -> ResumeSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Keys.resumeSnapshot) else { return nil }
        return try? JSONDecoder().decode(ResumeSnapshot.self, from: data)
    }

    static func normalizedServerURL(from value: String) -> URL? {
        URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func persistedOrLegacyCommandProfileID() -> String {
        if let persisted = UserDefaults.standard.string(forKey: Keys.commandProfileID), !persisted.isEmpty {
            return persisted
        }

        let legacy = UserDefaults.standard.string(forKey: "ios_client.launch_preset") ?? "shell"
        switch legacy {
        case "claudeCode":
            return "cc"
        case "codex":
            return "cx"
        default:
            return "shell"
        }
    }

    struct PersistedState {
        let serverURL: String
        let workspacePath: String
        let commandProfileID: String
        let launchMode: TerminalLaunchMode
        let selectedSessionID: String?
        let setupCompleted: Bool
        let autoConnectOnLaunch: Bool
        let autoResumeLastSession: Bool
        let trustedFingerprints: [String: String]
    }
}
