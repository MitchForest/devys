import ChatCore
import Foundation
import ServerProtocol

/// Persists conversation session metadata and messages to disk.
///
/// Directory layout:
/// ```
/// ~/Library/Application Support/devys/mac-server/conversations/
///   {session-id}/
///     session.json     — session metadata
///     messages.json    — materialized messages
///     events.ndjson    — append-only event log (managed by ConversationEventLog)
/// ```
final class ConversationSessionStore: Sendable {
    let baseDirectory: URL
    private let encoder = ServerJSONCoding.makeEncoder()
    private let decoder = ServerJSONCoding.makeDecoder()

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.baseDirectory = appSupport
                .appendingPathComponent("devys")
                .appendingPathComponent("mac-server")
                .appendingPathComponent("conversations")
        }
    }

    // MARK: - Save

    func saveSession(_ session: Session) throws {
        let dir = sessionDirectory(session.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try encoder.encode(session)
        try data.write(to: dir.appendingPathComponent("session.json"), options: .atomic)
    }

    func saveMessages(_ messages: [Message], sessionID: String) throws {
        let dir = sessionDirectory(sessionID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try encoder.encode(messages)
        try data.write(to: dir.appendingPathComponent("messages.json"), options: .atomic)
    }

    func loadAllSessions() -> [Session] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { dir in
            let sessionFile = dir.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: sessionFile) else { return nil }
            return try? decoder.decode(Session.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadMessages(sessionID: String) -> [Message] {
        let file = sessionDirectory(sessionID).appendingPathComponent("messages.json")
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([Message].self, from: data)) ?? []
    }

    // MARK: - Delete

    func deleteSession(_ sessionID: String) throws {
        let dir = sessionDirectory(sessionID)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Helpers

    func sessionDirectory(_ sessionID: String) -> URL {
        baseDirectory.appendingPathComponent(sessionID)
    }
}
