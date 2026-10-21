public import Foundation
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Devices

/// One signed-in device of the person, from `GET /api/devices`.
public struct Device: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let label: String?
    public let createdAt: String
    public let expiresAt: String
    /// The device making the request.
    public let current: Bool

    public init(id: String, label: String?, createdAt: String, expiresAt: String, current: Bool) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.current = current
    }

    enum CodingKeys: String, CodingKey {
        case id, label, current
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    public var addedDate: Date? { ServerDate.parse(createdAt) }
}

/// Timestamps as the server writes them: ISO 8601, with or without fractional seconds.
public enum ServerDate {
    public static func parse(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }
}

/// A single-use code that signs another device in as the same person, valid ten minutes.
public struct DeviceCode: Equatable, Sendable {
    public let code: String
    public let expiresAt: Date
    /// The server the code belongs to, so the link opens the right one.
    public let server: URL

    public init(code: String, expiresAt: Date, server: URL) {
        self.code = code
        self.expiresAt = expiresAt
        self.server = server
    }

    public var link: EnrollLink { EnrollLink(server: server, code: code) }
}

/// `devys://enroll?server=<url>&code=<64 hex>`: opens the app signed in on another device.
public struct EnrollLink: Equatable, Sendable {
    public let server: URL
    public let code: String

    public init(server: URL, code: String) {
        self.server = server
        self.code = code
    }

    /// Only an http(s) server and a 64-character hex code are accepted.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "devys", url.host()?.lowercased() == "enroll",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "server" })?.value,
              let server = URL(string: raw), let scheme = server.scheme?.lowercased(),
              ["http", "https"].contains(scheme), server.host() != nil,
              let code = items.first(where: { $0.name == "code" })?.value?.lowercased(),
              code.wholeMatch(of: /[a-f0-9]{64}/) != nil
        else { return nil }
        self.init(server: server, code: code)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "devys"
        components.host = "enroll"
        components.queryItems = [
            URLQueryItem(name: "server", value: server.absoluteString),
            URLQueryItem(name: "code", value: code)
        ]
        // A server URL carries ":" and "/"; encode them so the link survives cameras and chat apps.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "/", with: "%2F")
        return components.url!
    }
}

/// The name this device shows in the owner's device list.
public enum DeviceName {
    public static func current() async -> String? {
        #if os(macOS)
            Host.current().localizedName
        #elseif canImport(UIKit)
            await MainActor.run { UIDevice.current.name }
        #else
            nil
        #endif
    }
}

// MARK: - Businesses and their teams

/// A role an employee can be hired into, from `GET /api/roles`.
public struct RoleTemplate: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let responsibilities: String
    public let capabilities: [String]

    public init(id: String, name: String, summary: String, responsibilities: String, capabilities: [String]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.responsibilities = responsibilities
        self.capabilities = capabilities
    }

    /// Plain names for the templates, for places that only have the id.
    public static func displayName(_ id: String) -> String {
        switch id {
        case "operations": "Head of Operations"
        case "engineering": "Engineering"
        case "growth": "Growth"
        case "business-operations": "Business Operations"
        case "custom": "Custom"
        default: id
        }
    }

    /// The optional starting team a new business suggests.
    public static let startingTeam = ["engineering", "growth", "business-operations"]
}

/// A new business: its brief and the starting team hired alongside the Head of Operations.
public struct NewBusiness: Equatable, Sendable, Encodable {
    public let name: String
    public let brief: String
    public let team: [String]

    public init(name: String, brief: String = "", team: [String] = []) {
        self.name = name
        self.brief = brief
        self.team = team
    }
}

/// Hires from a template; a custom hire needs a name and responsibilities.
public struct Hire: Equatable, Sendable, Encodable {
    public let template: String
    public let name: String?
    public let responsibilities: String?
    public let model: String?

    public init(template: String, name: String? = nil, responsibilities: String? = nil, model: String? = nil) {
        self.template = template
        self.name = name
        self.responsibilities = responsibilities
        self.model = model
    }
}

/// Fields of an employee's profile to change; nil leaves one as it is.
public struct ProfileChange: Equatable, Sendable, Encodable {
    public let name: String?
    public let responsibilities: String?

    public init(name: String? = nil, responsibilities: String? = nil) {
        self.name = name
        self.responsibilities = responsibilities
    }
}

// MARK: - Work

/// A task the owner creates; given a project, it belongs to it.
public struct NewTask: Equatable, Sendable, Encodable {
    public let title: String
    public let owner: String
    public let objective: String?
    public let nextAction: String?
    /// ISO 8601.
    public let dueAt: String?
    public let projectId: String?

    public init(title: String, owner: String, objective: String? = nil, nextAction: String? = nil, dueAt: String? = nil, projectId: String? = nil) {
        self.title = title
        self.owner = owner
        self.objective = objective
        self.nextAction = nextAction
        self.dueAt = dueAt
        self.projectId = projectId
    }
}

/// A change to a commitment at the revision the owner saw. Absent fields stay as they are;
/// `.clear` removes a waiting condition or due date.
public struct CommitmentChange: Equatable, Sendable, Encodable {
    public enum Value: Equatable, Sendable {
        case set(String)
        case clear
    }

    public let expectedRevision: Int
    public var owner: String?
    public var state: CommitmentState?
    public var title: String?
    public var nextAction: String?
    public var waitCondition: Value?
    public var dueAt: Value?

    public init(
        expectedRevision: Int,
        owner: String? = nil,
        state: CommitmentState? = nil,
        title: String? = nil,
        nextAction: String? = nil,
        waitCondition: Value? = nil,
        dueAt: Value? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.owner = owner
        self.state = state
        self.title = title
        self.nextAction = nextAction
        self.waitCondition = waitCondition
        self.dueAt = dueAt
    }

    /// Hands the work to another employee; ready, so the dispatcher hands it over.
    public static func reassign(_ item: Commitment, to owner: String) -> Self {
        Self(expectedRevision: item.revision, owner: owner, state: .ready)
    }

    enum CodingKeys: String, CodingKey { case expectedRevision, owner, state, title, nextAction, waitCondition, dueAt }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expectedRevision, forKey: .expectedRevision)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(state?.rawValue, forKey: .state)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(nextAction, forKey: .nextAction)
        try encode(waitCondition, .waitCondition, in: &container)
        try encode(dueAt, .dueAt, in: &container)
    }

    private func encode(_ value: Value?, _ key: CodingKeys, in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch value {
        case .set(let text): try container.encode(text, forKey: key)
        case .clear: try container.encodeNil(forKey: key)
        case nil: break
        }
    }
}

// MARK: - Connections

/// The business's Google Drive connection, from `GET …/connections/google`.
public struct GoogleConnection: Equatable, Sendable, Decodable {
    public let configured: Bool
    public let connected: Bool

    public init(configured: Bool, connected: Bool) {
        self.configured = configured
        self.connected = connected
    }
}
