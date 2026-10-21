import Foundation

/// Every state a routine can be in: proposed by an employee, active once the owner decides.
public enum RoutineState: String, Equatable, Sendable, WireEnum {
    case proposed, active, paused
    /// A state this client does not know yet; shown, never set.
    case unknown
}

/// Whether a run speaks always, or only when it found something (a quiet check-in).
public enum RoutineNotify: String, Equatable, Sendable, WireEnum {
    case always
    case whenFound = "when_found"
    case unknown
}

/// When runs may happen, in the routine's time zone: `HH:MM` from `start` up to `end`, on `days`
/// (`mon`…; every day when absent).
public struct ActiveHours: Equatable, Sendable, Decodable {
    public let start: String
    public let end: String
    public let days: [String]?

    public init(start: String, end: String, days: [String]? = nil) {
        self.start = start
        self.end = end
        self.days = days
    }
}

/// What starts a run: a five-field cron expression in an IANA time zone, optionally within active
/// hours; or an event from a source whose fields equal every filter. A kind this client does not
/// know is `unknown`: the routine still shows, by its schedule in words.
public enum Trigger: Equatable, Sendable, Decodable {
    case cron(expression: String, timezone: String, hours: ActiveHours?)
    case event(source: String, type: String, filters: [String: JSONValue])
    case unknown

    enum CodingKeys: String, CodingKey { case kind, expression, timezone, hours, source, type, filters }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "cron":
            self = .cron(
                expression: try container.decode(String.self, forKey: .expression),
                timezone: try container.decode(String.self, forKey: .timezone),
                hours: try container.decodeIfPresent(ActiveHours.self, forKey: .hours)
            )
        case "event":
            self = .event(
                source: try container.decode(String.self, forKey: .source),
                type: try container.decode(String.self, forKey: .type),
                filters: try container.decode([String: JSONValue].self, forKey: .filters)
            )
        default:
            self = .unknown
        }
    }
}

/// Recurring or event-started work of one employee, for a responsibility or a project.
public struct Routine: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let employeeID: String
    /// The project it serves: its runs speak in that project's channel, else the employee's DM.
    public let projectID: String?
    public let title: String
    public let instruction: String
    public let trigger: Trigger
    /// The trigger in words, as the owner reads it.
    public let schedule: String
    public let notify: RoutineNotify
    public let state: RoutineState
    /// Each proposal is a new revision; the owner's decision activates exactly one.
    public let revision: Int
    /// The next scheduled run, while active.
    public let nextRunAt: String?
    public let lastRunAt: String?
    /// What the last run said, shortened, or "nothing to report".
    public let lastResult: String?
    /// `person:<id>` or `employee:<id>`.
    public let createdBy: String
    public let updatedAt: String

    public init(
        id: String,
        employeeID: String,
        projectID: String? = nil,
        title: String,
        instruction: String = "",
        trigger: Trigger = .cron(expression: "0 9 * * 1", timezone: "UTC", hours: nil),
        schedule: String = "At 09:00, only on Monday (UTC)",
        notify: RoutineNotify = .always,
        state: RoutineState = .active,
        revision: Int = 1,
        nextRunAt: String? = nil,
        lastRunAt: String? = nil,
        lastResult: String? = nil,
        createdBy: String = "",
        updatedAt: String = "2026-10-21T00:00:00.000Z"
    ) {
        self.id = id
        self.employeeID = employeeID
        self.projectID = projectID
        self.title = title
        self.instruction = instruction
        self.trigger = trigger
        self.schedule = schedule
        self.notify = notify
        self.state = state
        self.revision = revision
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastResult = lastResult
        self.createdBy = createdBy.isEmpty ? "employee:\(employeeID)" : createdBy
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, instruction, trigger, schedule, notify, state, revision
        case employeeID = "employee_id"
        case projectID = "project_id"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastResult = "last_result"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
    }
}

extension DevysHTTPClient {
    /// The business's routines; `employeeID` for an employee's desk, `projectID` for a project's overview.
    public func routines(_ session: DeviceSession, businessID: String, employeeID: String? = nil, projectID: String? = nil) async throws -> [Routine] {
        struct Page: Decodable { let routines: [Routine] }
        var request = authorized(session, path: "api/businesses/\(businessID)/routines")
        let query = [("employee", employeeID), ("project", projectID)].compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        if !query.isEmpty { request.url?.append(queryItems: query) }
        let page: Page = try await send(request)
        return page.routines
    }

    /// Pauses an active routine, or resumes a paused one; a proposed one is activated only by the
    /// owner's decision (409 says so).
    public func setRoutinePaused(_ session: DeviceSession, businessID: String, id: String, paused: Bool) async throws -> Routine {
        try await send(authorized(session, path: "api/businesses/\(businessID)/routines/\(id)/\(paused ? "pause" : "resume")", method: "POST"))
    }
}
