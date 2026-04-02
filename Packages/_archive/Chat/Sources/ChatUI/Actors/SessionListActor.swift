import ChatCore
import Foundation

public actor SessionListActor {
    private var sessionsByID: [String: Session] = [:]

    public init() {}

    public func replace(with sessions: [Session]) -> [Session] {
        sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return orderedSessions()
    }

    public func upsert(_ session: Session) -> [Session] {
        sessionsByID[session.id] = session
        return orderedSessions()
    }

    public func archive(sessionID: String, archivedAt: Date = .now) -> [Session] {
        guard let existing = sessionsByID[sessionID] else {
            return orderedSessions()
        }

        sessionsByID[sessionID] = Session(
            id: existing.id,
            title: existing.title,
            harnessType: existing.harnessType,
            model: existing.model,
            workspaceRoot: existing.workspaceRoot,
            branch: existing.branch,
            status: .archived,
            createdAt: existing.createdAt,
            updatedAt: archivedAt,
            archivedAt: archivedAt,
            lastMessagePreview: existing.lastMessagePreview,
            unreadCount: existing.unreadCount
        )

        return orderedSessions()
    }

    public func remove(sessionID: String) -> [Session] {
        sessionsByID.removeValue(forKey: sessionID)
        return orderedSessions()
    }

    public func session(id: String) -> Session? {
        sessionsByID[id]
    }

    public func allSessions() -> [Session] {
        orderedSessions()
    }

    private func orderedSessions() -> [Session] {
        sessionsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }
}
