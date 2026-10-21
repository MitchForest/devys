public import Dependencies
public import Foundation

/// A terminal on the owner's Mac. The host keeps it while devices come and go.
public struct TerminalInfo: Equatable, Sendable, Decodable, Identifiable, Hashable {
    public struct Exit: Equatable, Sendable, Decodable, Hashable {
        public let code: Int?
    }

    public let id: String
    public let title: String
    public let cwd: String
    /// The coding session it resumed, when it did.
    public let codingSessionID: String?
    public let exit: Exit?

    public init(id: String, title: String, cwd: String, codingSessionID: String? = nil, exit: Exit? = nil) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.codingSessionID = codingSessionID
        self.exit = exit
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cwd, exit
        case codingSessionID = "coding_session_id"
    }
}

/// Where a new terminal opens: the business folder, a work item's worktree, or a coding
/// agent's own CLI resumed on its session.
public enum TerminalTarget: Equatable, Sendable {
    case business
    case work(String)
    case resume(codingSessionID: String)
}

extension DevysHTTPClient {
    public func terminals(_ session: DeviceSession, businessID: String) async throws -> [TerminalInfo] {
        struct Page: Decodable { let terminals: [TerminalInfo] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/terminals"))
        return page.terminals
    }

    public func openTerminal(_ session: DeviceSession, businessID: String, target: TerminalTarget) async throws -> TerminalInfo {
        struct Body: Encodable { let work: String?; let resume: String?; let cols: Int; let rows: Int }
        let body: Body = switch target {
        case .business: Body(work: nil, resume: nil, cols: 100, rows: 30)
        case .work(let id): Body(work: id, resume: nil, cols: 100, rows: 30)
        case .resume(let id): Body(work: nil, resume: id, cols: 100, rows: 30)
        }
        return try await send(json(session, path: "api/businesses/\(businessID)/terminals", method: "POST", body: body))
    }

    public func closeTerminal(_ session: DeviceSession, businessID: String, terminalID: String) async throws {
        _ = try await raw(authorized(session, path: "api/businesses/\(businessID)/terminals/\(terminalID)/close", method: "POST"))
    }

    /// The WebSocket request for a terminal, resuming from `offset`, with the device's bearer token.
    public func terminalSocket(_ session: DeviceSession, businessID: String, terminalID: String, offset: Int) throws -> URLRequest {
        let address = session.server.appending(path: "api/businesses/\(businessID)/terminals/\(terminalID)/socket")
        guard var components = URLComponents(url: address, resolvingAgainstBaseURL: false) else { throw DevysHTTPError.invalidResponse }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "offset", value: String(offset))]
        guard let url = components.url else { throw DevysHTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "authorization")
        return request
    }
}

/// Terminals on the owner's Mac: listed, opened, closed, and attached to over a WebSocket.
public struct TerminalsClient: Sendable {
    public var list: @Sendable (_ businessID: String) async throws -> [TerminalInfo]
    public var open: @Sendable (_ businessID: String, TerminalTarget) async throws -> TerminalInfo
    public var close: @Sendable (_ businessID: String, _ terminalID: String) async throws -> Void
    public var socket: @Sendable (_ businessID: String, _ terminalID: String, _ offset: Int) async throws -> URLRequest

    public init(
        list: @escaping @Sendable (String) async throws -> [TerminalInfo],
        open: @escaping @Sendable (String, TerminalTarget) async throws -> TerminalInfo,
        close: @escaping @Sendable (String, String) async throws -> Void,
        socket: @escaping @Sendable (String, String, Int) async throws -> URLRequest
    ) {
        self.list = list
        self.open = open
        self.close = close
        self.socket = socket
    }

    public static func live(_ hub: SessionHub) -> Self {
        Self(
            list: { business in try await hub.call { api, session in try await api.terminals(session, businessID: business) } },
            open: { business, target in try await hub.call { api, session in try await api.openTerminal(session, businessID: business, target: target) } },
            close: { business, id in try await hub.call { api, session in try await api.closeTerminal(session, businessID: business, terminalID: id) } },
            socket: { business, id, offset in try await hub.call { api, session in try api.terminalSocket(session, businessID: business, terminalID: id, offset: offset) } }
        )
    }

    /// No Mac host: tests and previews.
    public static let none = Self(
        list: { _ in [] },
        open: { _, _ in throw DevysHTTPError.rejected(status: 503, message: "Terminals run in local mode only.") },
        close: { _, _ in },
        socket: { _, _, _ in throw DevysHTTPError.rejected(status: 503, message: "Terminals run in local mode only.") }
    )
}

nonisolated enum TerminalsClientKey: DependencyKey {
    static let liveValue = TerminalsClient.live(.shared)
    static let testValue = TerminalsClient.none
    static let previewValue = TerminalsClient.none
}

extension DependencyValues {
    public var terminalsClient: TerminalsClient {
        get { self[TerminalsClientKey.self] }
        set { self[TerminalsClientKey.self] = newValue }
    }
}
