import Foundation

// MARK: - Projects

/// A record a project shows: a reference, never a copy (an artifact or a business file).
public struct ProjectItem: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let ref: Ref

    public init(id: String, ref: Ref) {
        self.id = id
        self.ref = ref
    }
}

/// A spending limit in whole cents; it narrows, it never grants.
public struct Budget: Equatable, Sendable, Codable {
    public let cents: Int
    public let currency: String

    public init(cents: Int, currency: String = "USD") {
        self.cents = cents
        self.currency = currency
    }
}

/// A bounded initiative: a channel, its work and the records it touches.
public struct Project: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let goal: String?
    /// `YYYY-MM-DD`.
    public let deadline: String?
    public let budget: Budget?
    /// Answers in the channel unless the owner mentions someone.
    public let leadEmployeeID: String?
    public let memberIDs: [String]
    public let items: [ProjectItem]

    public init(
        id: String,
        name: String,
        goal: String? = nil,
        deadline: String? = nil,
        budget: Budget? = nil,
        leadEmployeeID: String? = nil,
        memberIDs: [String] = [],
        items: [ProjectItem] = []
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.deadline = deadline
        self.budget = budget
        self.leadEmployeeID = leadEmployeeID
        self.memberIDs = memberIDs
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case id, name, goal, deadline, budget, items
        case leadEmployeeID = "lead_employee_id"
        case memberIDs = "member_ids"
    }
}

/// A new project's name, goal, deadline, budget, lead and team. A nil goal, deadline or budget
/// is none; a nil lead lets the server pick Operations.
public struct ProjectChange: Equatable, Sendable, Encodable {
    public var name: String
    public var goal: String?
    public var deadline: String?
    public var budget: Budget?
    public var lead: String?
    public var members: [String]

    public init(name: String, goal: String? = nil, deadline: String? = nil, budget: Budget? = nil, lead: String? = nil, members: [String] = []) {
        self.name = name
        self.goal = goal
        self.deadline = deadline
        self.budget = budget
        self.lead = lead
        self.members = members
    }

    enum CodingKeys: String, CodingKey { case name, goal, deadline, budget, lead, members }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(goal, forKey: .goal)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(budget, forKey: .budget)
        try container.encodeIfPresent(lead, forKey: .lead)
        try container.encode(members, forKey: .members)
    }
}

// MARK: - Apps

/// An app in the directory, and whether this business has it.
public struct AppEntry: Equatable, Sendable, Decodable, Identifiable {
    /// System apps are always installed and never in the sidebar.
    public enum Kind: String, Equatable, Sendable, WireEnum { case system, business, unknown }

    /// A skill an app ships, which employees load by name.
    public struct Skill: Equatable, Sendable, Decodable {
        public let name: String
        public let description: String

        public init(name: String, description: String = "") {
            self.name = name
            self.description = description
        }
    }

    /// A kind of record the app owns, which a `Ref` names as `<app>/<kind>`.
    public struct Record: Equatable, Sendable, Decodable {
        public let kind: String
        public let title: String

        public init(kind: String, title: String) {
            self.kind = kind
            self.title = title
        }
    }

    public let id: String
    public let name: String
    public let icon: String
    public let summary: String
    public let kind: Kind
    public let records: [Record]
    /// The skills it ships, which employees load by name.
    public let skills: [Skill]
    public var installed: Bool
    public var pinned: Bool
    /// Installed and has something to show, so the sidebar lists it.
    public let visible: Bool

    public init(
        id: String,
        name: String,
        icon: String = "",
        summary: String = "",
        kind: Kind = .business,
        records: [Record] = [],
        skills: [Skill] = [],
        installed: Bool = true,
        pinned: Bool = true,
        visible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.summary = summary
        self.kind = kind
        self.records = records
        self.skills = skills
        self.installed = installed
        self.pinned = pinned
        self.visible = visible
    }
}

// MARK: - Home

/// One thing waiting on the owner: a request by its kind (a decision, an approve or a take over;
/// the whole request, so Needs you is answered from Home alone), or work that needs one.
public struct NeedsYouItem: Equatable, Sendable, Decodable, Identifiable {
    public enum Kind: String, Equatable, Sendable, WireEnum {
        case decision, approve, secret
        case takeOver = "take_over"
        case work, unknown
    }

    public let kind: Kind
    public let id: String
    public let title: String
    public let employeeID: String?
    public let workID: String?
    public let projectID: String?
    /// The request itself, when this is a decision.
    public let decision: Decision?
    /// For a routine's activation, the proposal it decides (at the revision asked about); nil
    /// when the routine has since moved to another revision, or for any other request.
    public let routine: Routine?

    public init(kind: Kind, id: String, title: String, employeeID: String? = nil, workID: String? = nil, projectID: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.employeeID = employeeID
        self.workID = workID
        self.projectID = projectID
        self.decision = nil
        self.routine = nil
    }

    /// A pending request as Home lists it.
    public init(_ decision: Decision, title: String, projectID: String? = nil, routine: Routine? = nil) {
        self.kind = switch decision.kind {
        case .approve: .approve
        case .takeOver: .takeOver
        case .secret: .secret
        case .decision, .unknown: .decision
        }
        self.id = decision.id
        self.title = title
        self.employeeID = decision.employeeID
        self.workID = decision.workItemID
        self.projectID = projectID
        self.decision = decision
        self.routine = routine
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        employeeID = try container.decodeIfPresent(String.self, forKey: .employeeID)
        workID = try container.decodeIfPresent(String.self, forKey: .workID)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        decision = [.decision, .approve, .takeOver, .secret].contains(kind) ? try Decision(from: decoder) : nil
        routine = try container.decodeIfPresent(Routine.self, forKey: .routine)
    }

    enum CodingKeys: String, CodingKey {
        case kind, id, title, routine
        case employeeID = "employee_id"
        case workID = "work_id"
        case projectID = "project_id"
    }
}

/// Work that moves, or is stuck.
public struct GlanceItem: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let employeeID: String
    public let projectID: String?
    public let state: WorkItemState
    public let waitCondition: String?
    public let dueAt: String?
    public let updatedAt: String

    public init(
        id: String,
        title: String,
        employeeID: String,
        projectID: String? = nil,
        state: WorkItemState = .inProgress,
        waitCondition: String? = nil,
        dueAt: String? = nil,
        updatedAt: String = "2026-10-19T00:00:00.000Z"
    ) {
        self.id = id
        self.title = title
        self.employeeID = employeeID
        self.projectID = projectID
        self.state = state
        self.waitCondition = waitCondition
        self.dueAt = dueAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, state
        case employeeID = "employee_id"
        case projectID = "project_id"
        case waitCondition = "wait_condition"
        case dueAt = "due_at"
        case updatedAt = "updated_at"
    }
}

/// What waits on the owner, and work at a glance.
public struct Home: Equatable, Sendable, Decodable {
    public struct Glance: Equatable, Sendable, Decodable {
        public let moving: [GlanceItem]
        public let stuck: [GlanceItem]

        public init(moving: [GlanceItem] = [], stuck: [GlanceItem] = []) {
            self.moving = moving
            self.stuck = stuck
        }
    }

    public let needsYou: [NeedsYouItem]
    public let glance: Glance

    public init(needsYou: [NeedsYouItem] = [], glance: Glance = Glance()) {
        self.needsYou = needsYou
        self.glance = glance
    }

    enum CodingKeys: String, CodingKey {
        case glance
        case needsYou = "needs_you"
    }

    /// The requests waiting on the owner.
    public var decisions: [Decision] { needsYou.compactMap(\.decision) }

    /// Home without one answered request, until the next read.
    public func answering(_ decisionID: String) -> Home {
        Home(needsYou: needsYou.filter { $0.id != decisionID }, glance: glance)
    }

    /// Whether Home's panel has anything to show; an empty one is never shown.
    public var isEmpty: Bool { needsYou.isEmpty && glance.moving.isEmpty && glance.stuck.isEmpty }
}

extension DevysHTTPClient {
    public func projects(_ session: DeviceSession, businessID: String) async throws -> [Project] {
        struct Page: Decodable { let projects: [Project] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/projects"))
        return page.projects
    }

    public func createProject(_ session: DeviceSession, businessID: String, _ project: ProjectChange) async throws -> Project {
        try await send(json(session, path: "api/businesses/\(businessID)/projects", method: "POST", body: project))
    }

    /// Keeps a record on a project's overview. Keeping it twice is harmless.
    public func addToProject(_ session: DeviceSession, businessID: String, projectID: String, ref: Ref) async throws {
        struct Body: Encodable { let ref: Ref }
        _ = try await raw(json(session, path: "api/businesses/\(businessID)/projects/\(projectID)/items", method: "POST", body: Body(ref: ref)))
    }

    /// Takes a record off a project; the record itself stays in its app.
    public func removeFromProject(_ session: DeviceSession, businessID: String, projectID: String, itemID: String) async throws {
        _ = try await raw(authorized(session, path: "api/businesses/\(businessID)/projects/\(projectID)/items/\(itemID)/remove", method: "POST"))
    }

    public func apps(_ session: DeviceSession, businessID: String) async throws -> [AppEntry] {
        struct Page: Decodable { let apps: [AppEntry] }
        let page: Page = try await send(authorized(session, path: "api/businesses/\(businessID)/apps"))
        return page.apps
    }

    public func installApp(_ session: DeviceSession, businessID: String, appID: String, install: Bool) async throws {
        _ = try await raw(authorized(session, path: "api/businesses/\(businessID)/apps/\(appID)/\(install ? "install" : "uninstall")", method: "POST"))
    }

    public func pinApp(_ session: DeviceSession, businessID: String, appID: String, pinned: Bool) async throws {
        struct Body: Encodable { let pinned: Bool }
        _ = try await raw(json(session, path: "api/businesses/\(businessID)/apps/\(appID)/pin", method: "POST", body: Body(pinned: pinned)))
    }

    public func home(_ session: DeviceSession, businessID: String) async throws -> Home {
        try await send(authorized(session, path: "api/businesses/\(businessID)/home"))
    }
}
