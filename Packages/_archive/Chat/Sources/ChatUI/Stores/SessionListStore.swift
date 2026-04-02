import ChatCore
import Foundation
import Observation

@MainActor
@Observable
public final class SessionListStore {
    public enum LoadingState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var sessions: [Session] = []
    public internal(set) var selectedSessionID: String?
    public private(set) var loadingState: LoadingState = .idle

    private let sessionListActor: SessionListActor

    public init(sessionListActor: SessionListActor = SessionListActor()) {
        self.sessionListActor = sessionListActor
    }

    public func replace(with sessions: [Session]) async {
        loadingState = .loading
        self.sessions = await sessionListActor.replace(with: sessions)
        selectedSessionID = coalescedSelection(from: selectedSessionID)
        loadingState = .loaded
    }

    public func upsert(_ session: Session) async {
        sessions = await sessionListActor.upsert(session)
        selectedSessionID = coalescedSelection(from: selectedSessionID)
    }

    public func archive(sessionID: String) async {
        sessions = await sessionListActor.archive(sessionID: sessionID)
        selectedSessionID = coalescedSelection(from: selectedSessionID)
    }

    public func delete(sessionID: String) async {
        sessions = await sessionListActor.remove(sessionID: sessionID)
        selectedSessionID = coalescedSelection(from: selectedSessionID)
    }

    public func select(sessionID: String?) {
        selectedSessionID = coalescedSelection(from: sessionID)
    }

    public func markFailure(_ message: String) {
        loadingState = .failed(message)
    }

    private func coalescedSelection(from requestedID: String?) -> String? {
        guard let requestedID else {
            return sessions.first?.id
        }
        if sessions.contains(where: { $0.id == requestedID }) {
            return requestedID
        }
        return sessions.first?.id
    }
}
