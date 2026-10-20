public import Dependencies
public import Foundation

/// A Codex or Claude Code session on a work item, with its live state read from the provider.
public struct CodingSession: Equatable, Sendable, Decodable, Identifiable {
    public enum State: String, Sendable, Decodable {
        case working, idle, interrupted, failed, unavailable
    }

    public let id: String
    public let provider: String
    public let purpose: String
    public let objective: String
    public let branch: String?
    public let worktree: String?
    public let state: State
    public let reply: String?
    public let diffStat: String
    public let error: String?

    public var providerName: String { provider == "codex" ? "Codex" : "Claude Code" }

    /// The "3 files changed, …" line of the diff stat.
    public var changeLine: String {
        diffStat.split(separator: "\n").first { $0.contains("changed") }.map { String($0).trimmingCharacters(in: .whitespaces) }
            ?? (diffStat.isEmpty ? "No changes yet" : "\(diffStat.split(separator: "\n").count) files changed")
    }

    public init(
        id: String,
        provider: String,
        purpose: String = "build",
        objective: String,
        branch: String? = nil,
        worktree: String? = nil,
        state: State,
        reply: String? = nil,
        diffStat: String = "",
        error: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.purpose = purpose
        self.objective = objective
        self.branch = branch
        self.worktree = worktree
        self.state = state
        self.reply = reply
        self.diffStat = diffStat
        self.error = error
    }
}

/// A worktree's changes against its base: a unified patch for the diff surface.
public struct WorkingDiff: Equatable, Sendable, Decodable {
    public let patch: String

    public init(patch: String) {
        self.patch = patch
    }
}

extension DevysHTTPClient {
    public func codingSessions(_ session: DeviceSession, businessID: String, workID: String) async throws -> [CodingSession] {
        struct Page: Decodable { let sessions: [CodingSession] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/work/\(workID)/sessions"))
        return page.sessions
    }

    public func sessionDiff(_ session: DeviceSession, businessID: String, workID: String, sessionID: String) async throws -> WorkingDiff {
        try await send(authorized(session, path: "api/businesses/\(businessID)/work/\(workID)/sessions/\(sessionID)/diff"))
    }

    /// Talks to the session directly; the server refuses unless the owner has taken the work over.
    public func steerSession(_ session: DeviceSession, businessID: String, workID: String, sessionID: String, text: String) async throws {
        struct Body: Encodable { let text: String }
        _ = try await raw(json(session, path: "api/businesses/\(businessID)/work/\(workID)/sessions/\(sessionID)/send", method: "POST", body: Body(text: text)))
    }

    public func stopSession(_ session: DeviceSession, businessID: String, workID: String, sessionID: String) async throws {
        _ = try await raw(authorized(session, path: "api/businesses/\(businessID)/work/\(workID)/sessions/\(sessionID)/interrupt", method: "POST"))
    }
}

/// Coding sessions on work items: listed and diffed from the provider each time, steered and stopped.
public struct CodingClient: Sendable {
    public var sessions: @Sendable (_ businessID: String, _ workID: String) async throws -> [CodingSession]
    public var diff: @Sendable (_ businessID: String, _ workID: String, _ sessionID: String) async throws -> WorkingDiff
    public var steer: @Sendable (_ businessID: String, _ workID: String, _ sessionID: String, _ text: String) async throws -> Void
    public var stop: @Sendable (_ businessID: String, _ workID: String, _ sessionID: String) async throws -> Void

    public init(
        sessions: @escaping @Sendable (String, String) async throws -> [CodingSession],
        diff: @escaping @Sendable (String, String, String) async throws -> WorkingDiff,
        steer: @escaping @Sendable (String, String, String, String) async throws -> Void,
        stop: @escaping @Sendable (String, String, String) async throws -> Void
    ) {
        self.sessions = sessions
        self.diff = diff
        self.steer = steer
        self.stop = stop
    }

    public static func live(_ hub: SessionHub) -> Self {
        Self(
            sessions: { business, work in try await hub.call { api, session in try await api.codingSessions(session, businessID: business, workID: work) } },
            diff: { business, work, id in
                try await hub.call { api, session in try await api.sessionDiff(session, businessID: business, workID: work, sessionID: id) }
            },
            steer: { business, work, id, text in
                try await hub.call { api, session in try await api.steerSession(session, businessID: business, workID: work, sessionID: id, text: text) }
            },
            stop: { business, work, id in
                try await hub.call { api, session in try await api.stopSession(session, businessID: business, workID: work, sessionID: id) }
            }
        )
    }

    /// No sessions anywhere: tests and previews that don't exercise coding.
    public static let none = Self(sessions: { _, _ in [] }, diff: { _, _, _ in WorkingDiff(patch: "") }, steer: { _, _, _, _ in }, stop: { _, _, _ in })
}

nonisolated enum CodingClientKey: DependencyKey {
    static let liveValue = CodingClient.live(.shared)
    static let testValue = CodingClient.none
    static let previewValue = CodingClient.none
}

extension DependencyValues {
    public var codingClient: CodingClient {
        get { self[CodingClientKey.self] }
        set { self[CodingClientKey.self] = newValue }
    }
}
