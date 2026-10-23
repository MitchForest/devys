public import DevysCharacter
import Foundation

/// The open business and its team as the workspace shows them. Every section
/// renders real records or an honest empty state; nothing here is sample data.
public struct WorkspaceSnapshot: Equatable, Sendable {
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

/// An employee of the current business, from `GET /api/businesses/:id`. What it is doing comes
/// from its runtime status, not from this record.
public struct Employee: Equatable, Sendable, Identifiable, Decodable {
    public let id: String
    public var name: String
    /// The employee's responsibilities, in the owner's words.
    public var responsibilities: String
    /// The role template it was hired from: chief-of-staff, admin, finance, engineering, growth or custom.
    public var template: String
    public var avatar: AvatarSpec
    public var summary: String
    /// Takes no actions until the owner resumes it.
    public var paused = false
    /// nil shows `avatar`, the default Face.
    public var look: Look?
    /// The id of the model the employee thinks with, from the model catalog.
    public var model: String

    public init(
        id: String,
        name: String,
        responsibilities: String,
        template: String = "custom",
        avatar: AvatarSpec? = nil,
        summary: String? = nil,
        paused: Bool = false,
        look: Look? = nil,
        model: String
    ) {
        self.id = id
        self.name = name
        self.responsibilities = responsibilities
        self.template = template
        self.avatar = avatar ?? Self.face(for: id)
        self.summary = summary ?? responsibilities
        self.paused = paused
        self.look = look
        self.model = model
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            responsibilities: try container.decode(String.self, forKey: .responsibilities),
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

    /// The Chief of Staff can't be retired.
    public var isChiefOfStaff: Bool { template == "chief-of-staff" }

    enum CodingKeys: String, CodingKey { case id, name, responsibilities, template, paused, look, model }
}

extension WorkspaceSnapshot {
    /// Nothing loaded yet: no business and no team.
    public static let empty = WorkspaceSnapshot(business: Business(id: "", name: ""), employees: [])
}
