public import Foundation

/// A signed-in device: the server it enrolled with and its bearer session.
/// The token is a credential; it lives only in the Keychain and request headers.
public struct DeviceSession: Equatable, Sendable, Codable {
    public let server: URL
    public let token: String

    public init(server: URL, token: String) {
        self.server = server
        self.token = token
    }
}

public struct Person: Equatable, Sendable, Decodable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// `GET /api/me`: who is signed in and the businesses they belong to.
public struct Account: Equatable, Sendable, Decodable {
    public let person: Person
    public let businesses: [Business]

    public init(person: Person, businesses: [Business]) {
        self.person = person
        self.businesses = businesses
    }
}

/// `GET /api/businesses/:id`: the business's team and recent files.
public struct BusinessDetail: Equatable, Sendable, Decodable {
    public let business: Business
    public let employees: [Employee]
    /// The people who are members, so a client can name who took work over.
    public let members: [Person]
    public let artifacts: [Artifact]

    public init(business: Business, employees: [Employee], members: [Person] = [], artifacts: [Artifact]) {
        self.business = business
        self.employees = employees
        self.members = members
        self.artifacts = artifacts
    }
}

/// One employee of one business: the address of its runtime and conversation.
public struct EmployeeScope: Equatable, Hashable, Sendable {
    public let businessID: String
    public let employeeID: String

    public init(businessID: String, employeeID: String) {
        self.businessID = businessID
        self.employeeID = employeeID
    }

    var path: String { "api/businesses/\(businessID)/employees/\(employeeID)" }
}

/// `GET …/employees/:id/status`: the employee runtime's current state.
public struct EmployeeStatus: Equatable, Sendable, Decodable {
    public let state: RuntimeState

    public init(state: RuntimeState) {
        self.state = state
    }
}

public struct RuntimeState: Equatable, Sendable, Decodable {
    public let run: Run?
    public let inbox: [InboxEntry]
    public let outbox: [OutboxEntry]
    /// Absent until the runtime has used a model.
    public let usage: RuntimeUsage?

    public init(run: Run?, inbox: [InboxEntry], outbox: [OutboxEntry], usage: RuntimeUsage? = nil) {
        self.run = run
        self.inbox = inbox
        self.outbox = outbox
        self.usage = usage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        run = try container.decodeIfPresent(Run.self, forKey: .run)
        inbox = try container.decode([InboxEntry].self, forKey: .inbox)
        outbox = try container.decode([OutboxEntry].self, forKey: .outbox)
        // Spend is informational: a shape this client doesn't know never hides the status.
        usage = try? container.decodeIfPresent(RuntimeUsage.self, forKey: .usage)
    }

    enum CodingKeys: String, CodingKey { case run, inbox, outbox, usage }

    public struct Run: Equatable, Sendable, Decodable {
        public let id: String
        public let stopped: Bool
        /// Milliseconds since 1970, as the runtime reports it.
        public let deadline: Double?

        public init(id: String, stopped: Bool, deadline: Double?) {
            self.id = id
            self.stopped = stopped
            self.deadline = deadline
        }
    }
}

public struct InboxEntry: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let text: String?
    /// Milliseconds since 1970.
    public let receivedAt: Double
    public let status: String

    public init(id: String, text: String?, receivedAt: Double, status: String) {
        self.id = id
        self.text = text
        self.receivedAt = receivedAt
        self.status = status
    }

    public var receivedDate: Date { Date(timeIntervalSince1970: receivedAt / 1000) }
}

public struct OutboxEntry: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let text: String
    /// `pending`, `sent`, `uncertain` or `cancelled`; uncertain is never shown as sent.
    public let status: String

    public init(id: String, text: String, status: String) {
        self.id = id
        self.text = text
        self.status = status
    }
}

public struct Artifact: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let filename: String
    public let contentType: String
    public let byteLength: Int
    public let createdAt: String

    public init(id: String, filename: String, contentType: String, byteLength: Int, createdAt: String) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
        self.byteLength = byteLength
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, filename
        case contentType = "content_type"
        case byteLength = "byte_length"
        case createdAt = "created_at"
    }
}

/// One remembered claim from `GET /api/memory`, with where it came from.
public struct MemoryClaim: Equatable, Sendable, Decodable, Identifiable {
    public let key: String
    public let content: String
    public let sourceKind: String
    public let revision: Int
    public let updatedAt: String

    public var id: String { key }

    public init(key: String, content: String, sourceKind: String, revision: Int, updatedAt: String) {
        self.key = key
        self.content = content
        self.sourceKind = sourceKind
        self.revision = revision
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case key, content, revision
        case sourceKind = "source_kind"
        case updatedAt = "updated_at"
    }
}

public struct MemoryPage: Equatable, Sendable, Decodable {
    public let items: [MemoryClaim]
    public let next: String?
}

/// A tapback on an employee's message. Silent: the employee reads it as context next turn.
public struct Reaction: Equatable, Sendable, Encodable {
    public let targetId: String
    public let targetText: String
    public let emoji: String
    public let isOn: Bool

    public init(targetId: String, targetText: String, emoji: String, isOn: Bool) {
        self.targetId = targetId
        self.targetText = targetText
        self.emoji = emoji
        self.isOn = isOn
    }

    enum CodingKeys: String, CodingKey {
        case targetId, targetText, emoji
        case isOn = "on"
    }
}

/// `auto` runs inside the grant; `ask` needs the owner's approval each time.
public enum AccessMode: String, Equatable, Sendable, Codable { case auto, ask }

/// One standing permission an employee holds.
public struct AccessGrant: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let capability: String
    public let mode: AccessMode
    public let description: String
    public let effect: String
    /// Host names a public-web grant is limited to, when it is.
    public let hosts: [String]

    public init(id: String, capability: String, mode: AccessMode, description: String, effect: String, hosts: [String] = []) {
        self.id = id
        self.capability = capability
        self.mode = mode
        self.description = description
        self.effect = effect
        self.hosts = hosts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            capability: try container.decode(String.self, forKey: .capability),
            mode: try container.decode(AccessMode.self, forKey: .mode),
            description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
            effect: try container.decodeIfPresent(String.self, forKey: .effect) ?? "read",
            hosts: (try container.decodeIfPresent(GrantLimits.self, forKey: .constraints))?.hosts ?? []
        )
    }

    enum CodingKeys: String, CodingKey { case id, capability, mode, description, effect, constraints }
}

/// The limit fields a grant may carry; only public-web hosts exist today.
struct GrantLimits: Decodable {
    let hosts: [String]?
}

/// A capability the employee could be granted.
public struct GrantableCapability: Equatable, Sendable, Decodable, Identifiable {
    public let capability: String
    public let description: String
    public let effect: String
    public var id: String { capability }

    public init(capability: String, description: String, effect: String) {
        self.capability = capability
        self.description = description
        self.effect = effect
    }
}

/// What an employee may do: its grants and the capabilities it could be granted.
public struct AccessList: Equatable, Sendable, Decodable {
    public let grants: [AccessGrant]
    public let available: [GrantableCapability]

    public init(grants: [AccessGrant], available: [GrantableCapability]) {
        self.grants = grants
        self.available = available
    }
}

/// Any JSON value, for showing a request's exact input as it will run.
public indirect enum JSONValue: Equatable, Sendable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Plain text: strings as written, everything else compact.
    public var text: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted(.number.grouping(.never))
        case .bool(let value): value ? "yes" : "no"
        case .null: "none"
        case .array(let values): values.map(\.text).joined(separator: ", ")
        case .object(let fields): fields.keys.sorted().map { "\($0): \(fields[$0]!.text)" }.joined(separator: "; ")
        }
    }

    /// Top-level fields in key order, for a review card.
    public var fields: [(key: String, value: String)] {
        guard case .object(let fields) = self else { return [("input", text)] }
        return fields.keys.sorted().map { ($0, fields[$0]!.text) }
    }
}

public enum CommitmentState: String, Equatable, Sendable, Decodable, CaseIterable {
    case proposed
    case ready
    case inProgress = "in_progress"
    case waiting
    case needsDecision = "needs_decision"
    case completed
    case cancelled

    public var isOpen: Bool { self != .completed && self != .cancelled }
}

/// What was done and by whom, recorded when work completes.
public struct CommitmentEvidence: Equatable, Sendable, Decodable {
    public struct Check: Equatable, Sendable, Decodable {
        public let command: String
        public let exitCode: Int?

        public init(command: String, exitCode: Int?) {
            self.command = command
            self.exitCode = exitCode
        }
    }

    /// A deploy of the commit: its stage, the URL checked, and whether it answered.
    public struct Deploy: Equatable, Sendable, Decodable {
        public let stage: String
        public let url: String?
        public let live: Bool

        public init(stage: String, url: String?, live: Bool) {
            self.stage = stage
            self.url = url
            self.live = live
        }
    }

    public let author: String
    public let note: String
    public let recordedAt: String
    /// A coding result names its commit, the check run against it, what changed and its pull request.
    public let commit: String?
    public let check: Check?
    public let changes: String?
    public let pullRequest: String?
    public let deploy: Deploy?

    public init(
        author: String,
        note: String,
        recordedAt: String,
        commit: String? = nil,
        check: Check? = nil,
        changes: String? = nil,
        pullRequest: String? = nil,
        deploy: Deploy? = nil
    ) {
        self.author = author
        self.note = note
        self.recordedAt = recordedAt
        self.commit = commit
        self.check = check
        self.changes = changes
        self.pullRequest = pullRequest
        self.deploy = deploy
    }

    enum CodingKeys: String, CodingKey {
        case note, commit, check, changes, pullRequest, deploy
        case author = "by"
        case recordedAt = "at"
    }
}

/// A coding result at a glance, read from a work item's evidence (the web's `outcomeOf`).
public struct CodingOutcome: Equatable, Sendable {
    public let commit: String
    public let changes: String?
    public let checkPassed: Bool?
    public let pullRequest: URL?
    /// The latest deploy to each stage, production first.
    public let deploys: [CommitmentEvidence.Deploy]

    /// The pull request's "PR #12", or nil without one.
    public var pullRequestLabel: String? {
        guard let pullRequest else { return nil }
        let parts = pullRequest.pathComponents
        if let index = parts.firstIndex(of: "pull"), index + 1 < parts.count { return "PR #\(parts[index + 1])" }
        return "Pull request"
    }

    public init?(_ evidence: [CommitmentEvidence]) {
        let coding = evidence.filter { $0.commit != nil }
        guard let last = coding.last?.commit else { return nil }
        commit = String(last.prefix(7))
        changes = coding.last { $0.changes?.isEmpty == false }?.changes
        checkPassed = coding.last { $0.check != nil }?.check.map { $0.exitCode == 0 }
        pullRequest = coding.last { $0.pullRequest != nil }?.pullRequest.flatMap(URL.init(string:))
        deploys = ["production", "preview"].compactMap { stage in coding.last { $0.deploy?.stage == stage }?.deploy }
    }
}

/// What the business owes: who is accountable, what's next, and evidence when done.
public struct Commitment: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let ownerEmployeeID: String
    public let title: String
    public let objective: String
    public let nextAction: String
    public let waitCondition: String?
    public let dueAt: String?
    public let state: CommitmentState
    public let evidence: [CommitmentEvidence]
    public let revision: Int
    public let takenOverBy: String?
    public let updatedAt: String

    public init(
        id: String,
        ownerEmployeeID: String,
        title: String,
        objective: String = "",
        nextAction: String = "",
        waitCondition: String? = nil,
        dueAt: String? = nil,
        state: CommitmentState = .ready,
        evidence: [CommitmentEvidence] = [],
        revision: Int = 1,
        takenOverBy: String? = nil,
        updatedAt: String = "2026-10-19T00:00:00.000Z"
    ) {
        self.id = id
        self.ownerEmployeeID = ownerEmployeeID
        self.title = title
        self.objective = objective
        self.nextAction = nextAction
        self.waitCondition = waitCondition
        self.dueAt = dueAt
        self.state = state
        self.evidence = evidence
        self.revision = revision
        self.takenOverBy = takenOverBy
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, objective, state, evidence, revision
        case ownerEmployeeID = "owner_employee_id"
        case nextAction = "next_action"
        case waitCondition = "wait_condition"
        case dueAt = "due_at"
        case takenOverBy = "taken_over_by"
        case updatedAt = "updated_at"
    }
}

/// A request an employee made that the owner approves or rejects once.
public struct Decision: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let employeeID: String
    public let capability: String
    public let input: JSONValue
    public let commitmentID: String?
    /// pending, approved, rejected, or used (an approval that ran).
    public let status: String
    public let requestedAt: String
    public let expiresAt: String

    public init(
        id: String,
        employeeID: String,
        capability: String,
        input: JSONValue,
        commitmentID: String? = nil,
        status: String = "pending",
        requestedAt: String = "2026-10-19T00:00:00.000Z",
        expiresAt: String = "2026-10-20T00:00:00.000Z"
    ) {
        self.id = id
        self.employeeID = employeeID
        self.capability = capability
        self.input = input
        self.commitmentID = commitmentID
        self.status = status
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id, capability, input, status
        case employeeID = "employee_id"
        case commitmentID = "commitment_id"
        case requestedAt = "requested_at"
        case expiresAt = "expires_at"
    }
}

/// A record shown in a space: a reference to a commitment or a saved file, never a copy.
public struct SpaceItem: Equatable, Sendable, Decodable, Identifiable {
    public enum Kind: String, Equatable, Sendable, Codable { case commitment, artifact, file }

    public let id: String
    public let kind: Kind
    public let ref: String

    public init(id: String, kind: Kind, ref: String) {
        self.id = id
        self.kind = kind
        self.ref = ref
    }
}

/// A persistent place for an area of the business. It shows records; it owns none.
public struct Space: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let purpose: String
    /// Answers the space's conversation until someone else speaks or is mentioned.
    public let leadEmployeeID: String?
    public let items: [SpaceItem]

    public init(id: String, name: String, purpose: String = "", leadEmployeeID: String? = nil, items: [SpaceItem] = []) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.leadEmployeeID = leadEmployeeID
        self.items = items
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            purpose: try container.decodeIfPresent(String.self, forKey: .purpose) ?? "",
            leadEmployeeID: try container.decodeIfPresent(String.self, forKey: .leadEmployeeID),
            items: try container.decodeIfPresent([SpaceItem].self, forKey: .items) ?? []
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, purpose, items
        case leadEmployeeID = "lead_employee_id"
    }

    public func refs(_ kind: SpaceItem.Kind) -> [String] {
        items.filter { $0.kind == kind }.map(\.ref)
    }
}
