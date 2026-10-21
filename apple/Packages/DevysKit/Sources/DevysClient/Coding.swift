public import Dependencies
import Foundation

/// A Codex or Claude Code session on a work item, with its live state read from the provider.
public struct CodingSession: Equatable, Sendable, Decodable, Identifiable {
    public enum State: String, Sendable, WireEnum {
        case working, idle, interrupted, failed, unavailable, unknown
    }

    public let id: String
    public let provider: String
    public let purpose: String
    public let objective: String
    /// The commit the session's branch started from, which its diff is against.
    public let baseCommit: String?
    public let branch: String?
    public let worktree: String?
    public let state: State
    public let reply: String?
    public let diffStat: String
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case id, provider, purpose, objective, branch, worktree, state, reply, error
        case baseCommit = "base_commit"
        case diffStat = "diff_stat"
    }

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
        baseCommit: String? = nil,
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
        self.baseCommit = baseCommit
        self.branch = branch
        self.worktree = worktree
        self.state = state
        self.reply = reply
        self.diffStat = diffStat
        self.error = error
    }
}

/// One step of what a coding session did, read from the harness when asked.
public struct TranscriptEntry: Equatable, Sendable, Decodable {
    public enum Kind: String, Sendable, WireEnum { case prompt, reply, plan, command, files, tool, unknown }

    public let kind: Kind
    public let text: String
    public let detail: String?
    public let failed: Bool?

    public init(kind: Kind, text: String, detail: String? = nil, failed: Bool? = nil) {
        self.kind = kind
        self.text = text
        self.detail = detail
        self.failed = failed
    }
}

/// A coding session the owner drives from the start: its new work item.
public struct NewCodingSession: Encodable, Sendable {
    public let clientID: String
    /// Who it goes to on hand-back.
    public let employee: String
    public let provider: String
    public let objective: String
    public let repository: String?
    public let newRepository: String?

    public init(employee: String, provider: String, objective: String, repository: String?, newRepository: String?) {
        self.clientID = UUID().uuidString.lowercased()
        self.employee = employee
        self.provider = provider
        self.objective = objective
        self.repository = repository
        self.newRepository = newRepository
    }

    enum CodingKeys: String, CodingKey {
        case employee, provider, objective, repository
        case clientID = "client_id"
        case newRepository = "new_repository"
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

    public func sessionTranscript(_ session: DeviceSession, businessID: String, workID: String, sessionID: String) async throws -> [TranscriptEntry] {
        struct Page: Decodable { let entries: [TranscriptEntry] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/work/\(workID)/sessions/\(sessionID)/transcript"))
        return page.entries
    }

    /// Starts a session the owner drives; returns its new work item's id.
    public func startCoding(_ session: DeviceSession, businessID: String, _ start: NewCodingSession) async throws -> String {
        struct Started: Decodable { let work: String }
        let started: Started = try await send(json(session, path: "api/businesses/\(businessID)/coding", method: "POST", body: start))
        return started.work
    }

    /// Work items that have coding sessions, newest first.
    public func codingWork(_ session: DeviceSession, businessID: String) async throws -> [String] {
        struct Page: Decodable { let work: [String] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/coding"))
        return page.work
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
    public var transcript: @Sendable (_ businessID: String, _ workID: String, _ sessionID: String) async throws -> [TranscriptEntry]
    /// Returns the new work item's id.
    public var start: @Sendable (_ businessID: String, NewCodingSession) async throws -> String
    /// Work items that have coding sessions, newest first.
    public var work: @Sendable (_ businessID: String) async throws -> [String]

    public init(
        sessions: @escaping @Sendable (String, String) async throws -> [CodingSession],
        diff: @escaping @Sendable (String, String, String) async throws -> WorkingDiff,
        steer: @escaping @Sendable (String, String, String, String) async throws -> Void,
        stop: @escaping @Sendable (String, String, String) async throws -> Void,
        transcript: @escaping @Sendable (String, String, String) async throws -> [TranscriptEntry] = { _, _, _ in [] },
        start: @escaping @Sendable (String, NewCodingSession) async throws -> String = { _, _ in "" },
        work: @escaping @Sendable (String) async throws -> [String] = { _ in [] }
    ) {
        self.sessions = sessions
        self.diff = diff
        self.steer = steer
        self.stop = stop
        self.transcript = transcript
        self.start = start
        self.work = work
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
            },
            transcript: { business, work, id in
                try await hub.call { api, session in try await api.sessionTranscript(session, businessID: business, workID: work, sessionID: id) }
            },
            start: { business, start in
                try await hub.call { api, session in try await api.startCoding(session, businessID: business, start) }
            },
            work: { business in try await hub.call { api, session in try await api.codingWork(session, businessID: business) } }
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
