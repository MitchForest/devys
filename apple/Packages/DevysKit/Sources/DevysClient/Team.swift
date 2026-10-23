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
        case "chief-of-staff": "Chief of Staff"
        case "engineering": "Engineering"
        case "growth": "Growth"
        case "admin": "Admin"
        case "finance": "Finance"
        case "custom": "Custom"
        default: id
        }
    }

    /// The optional starting team a new business suggests.
    public static let startingTeam = ["admin", "finance", "growth", "engineering"]
}

/// A new business: its brief and the starting team hired alongside the Chief of Staff.
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

/// A work item the owner creates; given a project, it belongs to it.
public struct NewWorkItem: Equatable, Sendable, Encodable {
    public let title: String
    public let owner: String
    public let objective: String?
    public let nextAction: String?
    /// ISO 8601.
    public let dueAt: String?
    public let projectID: String?

    public init(title: String, owner: String, objective: String? = nil, nextAction: String? = nil, dueAt: String? = nil, projectID: String? = nil) {
        self.title = title
        self.owner = owner
        self.objective = objective
        self.nextAction = nextAction
        self.dueAt = dueAt
        self.projectID = projectID
    }

    enum CodingKeys: String, CodingKey {
        case title, owner, objective
        case nextAction = "next_action"
        case dueAt = "due_at"
        case projectID = "project_id"
    }
}

/// A change to a work item at the revision the owner saw. Absent fields stay as they are;
/// `.clear` removes a waiting condition or due date.
public struct WorkItemChange: Equatable, Sendable, Encodable {
    public enum Value: Equatable, Sendable {
        case set(String)
        case clear
    }

    public let expectedRevision: Int
    public var owner: String?
    public var state: WorkItemState?
    public var title: String?
    public var nextAction: String?
    public var waitCondition: Value?
    public var dueAt: Value?

    public init(
        expectedRevision: Int,
        owner: String? = nil,
        state: WorkItemState? = nil,
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
    public static func reassign(_ item: WorkItem, to owner: String) -> Self {
        Self(expectedRevision: item.revision, owner: owner, state: .ready)
    }

    enum CodingKeys: String, CodingKey {
        case owner, state, title
        case expectedRevision = "expected_revision"
        case nextAction = "next_action"
        case waitCondition = "wait_condition"
        case dueAt = "due_at"
    }

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
