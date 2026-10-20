public import DevysCharacter
import Foundation

/// The open business and its team as the workspace shows them. Every section
/// renders real records or an honest empty state; nothing here is sample data.
public struct WorkspacePreview: Equatable, Sendable {
    public var business: Business
    public var employees: [Employee]

    public init(business: Business, employees: [Employee]) {
        self.business = business
        self.employees = employees
    }

    public var businessName: String { business.name }
}

/// A business the person is a member of, from `GET /api/me`.
public struct Business: Equatable, Sendable, Identifiable, Decodable {
    public let id: String
    public var name: String
    /// nil shows the initial on its tile.
    public var look: Look?
    /// What the business does, its goals and constraints; every employee's instructions include it.
    public var brief: String

    public init(id: String, name: String, look: Look? = nil, brief: String = "") {
        self.id = id
        self.name = name
        self.look = look
        self.brief = brief
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            look: try container.decodeIfPresent(Look.self, forKey: .look),
            brief: try container.decodeIfPresent(String.self, forKey: .brief) ?? ""
        )
    }

    enum CodingKeys: String, CodingKey { case id, name, look, brief }

    public var initial: String { name.first.map { String($0).uppercased() } ?? "·" }

    /// A `BusinessTile.Tint` raw value, stable for the business's id.
    public var tint: String {
        let tints = ["blue", "orange", "green", "purple", "pink"]
        return tints[id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % tints.count]
    }
}

public struct PreviewEvent: Equatable, Sendable, Identifiable {
    public let id: String
    public let time: String
    public let text: String
}

/// An employee of the current business, from `GET /api/businesses/:id`. Activity, events and
/// access are filled in from other sources as they become real; until then they stay empty.
public struct Employee: Equatable, Sendable, Identifiable, Decodable {
    public let id: String
    public var name: String
    /// The employee's responsibilities, in the owner's words.
    public var role: String
    /// The role template it was hired from: operations, engineering, growth, business-operations or custom.
    public var template: String
    public var avatar: AvatarSpec
    public var activity: Activity = .idle
    public var summary: String
    public var events: [PreviewEvent] = []
    /// Takes no actions until the owner resumes it.
    public var paused = false
    /// nil shows `avatar`, the default Face.
    public var look: Look?
    /// The id of the model the employee thinks with, from the model catalog.
    public var model: String

    public enum Activity: String, Equatable, Sendable {
        case working
        case waiting
        case idle
    }

    public init(
        id: String,
        name: String,
        role: String,
        template: String = "custom",
        avatar: AvatarSpec? = nil,
        activity: Activity = .idle,
        summary: String? = nil,
        events: [PreviewEvent] = [],
        paused: Bool = false,
        look: Look? = nil,
        model: String = ModelCatalog.fixture.defaults.employee
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.template = template
        self.avatar = avatar ?? Self.face(for: id)
        self.activity = activity
        self.summary = summary ?? role
        self.events = events
        self.paused = paused
        self.look = look
        self.model = model
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            role: try container.decode(String.self, forKey: .role),
            template: try container.decodeIfPresent(String.self, forKey: .template) ?? "custom",
            paused: try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false,
            look: try container.decodeIfPresent(Look.self, forKey: .look),
            model: try container.decode(String.self, forKey: .model)
        )
    }

    /// A stable Face for an employee who hasn't been given one.
    static func face(for id: String) -> AvatarSpec {
        let value = id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        let magnitude = value.magnitude
        return AvatarSpec(
            palette: AvatarPalette.allCases[Int(magnitude % UInt(AvatarPalette.allCases.count))],
            shape: AvatarShape.allCases[Int((magnitude / 10) % UInt(AvatarShape.allCases.count))],
            seed: Int(magnitude % 97)
        )
    }

    /// The Head of Operations can't be retired.
    public var isOperations: Bool { template == "operations" }

    enum CodingKeys: String, CodingKey { case id, name, role, template, paused, look, model }
}

extension WorkspacePreview {
    /// Nothing loaded yet: no business and no team.
    public static let empty = WorkspacePreview(business: Business(id: "", name: ""), employees: [])

    /// Fixture businesses for previews and tests; the live app never shows them.
    public static let acmeLaunch = WorkspacePreview(
        business: Business(id: "acme", name: "Acme"),
        employees: [
            Employee(
                id: "ops",
                name: "Head of Operations",
                role: "Coordinates launch work and brings you decisions",
                template: "operations",
                avatar: AvatarSpec(palette: .blue, shape: .roundedSquare, seed: 7),
                activity: .working,
                summary: "Updating the launch plan after your note on email",
                events: [
                    PreviewEvent(id: "ops-1", time: "2:40 PM", text: "Asked Business Ops to compare Workspace plans"),
                    PreviewEvent(id: "ops-2", time: "11:40 AM", text: "Saved the launch checklist to Files")
                ]
            ),
            Employee(
                id: "engineering",
                name: "Engineering",
                role: "Builds, verifies and deploys Acme",
                template: "engineering",
                avatar: AvatarSpec(palette: .green, shape: .hexagon, seed: 3),
                activity: .idle,
                summary: "Ready to deploy a preview once GitHub is connected",
                events: [PreviewEvent(id: "eng-1", time: "10:05 AM", text: "Checked the Acme launch gates locally")]
            ),
            Employee(
                id: "growth",
                name: "Growth",
                role: "Measurement, PR and campaigns",
                template: "growth",
                avatar: AvatarSpec(palette: .orange, shape: .blob, seed: 11),
                activity: .waiting,
                summary: "Waiting on your approval to send the PR inquiry"
            ),
            Employee(
                id: "business-ops",
                name: "Business Operations",
                role: "Accounts, purchases and suppliers",
                template: "business-operations",
                avatar: AvatarSpec(palette: .purple, shape: .capsule, seed: 5),
                activity: .working,
                summary: "Comparing Workspace plans"
            )
        ]
    )

    public static let scribbleGrowth = WorkspacePreview(
        business: Business(id: "scribble", name: "Scribble"),
        employees: [
            Employee(
                id: "scribble-ops",
                name: "Head of Operations",
                role: "Coordinates Scribble's growth work",
                template: "operations",
                avatar: AvatarSpec(palette: .teal, shape: .circle, seed: 2),
                activity: .idle,
                summary: "Watching sign-ups and support"
            )
        ]
    )
}
