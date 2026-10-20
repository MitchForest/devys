import DevysClient
import Foundation
import Testing

@Suite("Devices, team, spaces and work API")
struct TeamAPITests {
    private actor Recorder {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
    }

    private static let server = URL(string: "https://devys.test")!
    private static let session = DeviceSession(server: server, token: "tok")
    private static let scope = EmployeeScope(businessID: "b1", employeeID: "e1")

    private func api(status: Int = 200, body: String, recorder: Recorder) -> DevysHTTPClient {
        DevysHTTPClient { request in
            await recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private func sent(_ recorder: Recorder) async throws -> (URLRequest, [String: Any]) {
        let request = try #require(await recorder.requests.last)
        let body = try request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return (request, body ?? [:])
    }

    @Test("Enrollment sends the device's name with the code")
    func enrollWithName() async throws {
        let recorder = Recorder()
        _ = try await api(body: #"{"sessionToken":"abc"}"#, recorder: recorder).enroll(server: Self.server, code: "f00d", name: "Mitch's iPad")
        let (_, body) = try await sent(recorder)
        #expect(body["token"] as? String == "f00d")
        #expect(body["name"] as? String == "Mitch's iPad")
    }

    @Test("Devices list with the current one marked; a code carries its server; revoking posts to the device")
    func devices() async throws {
        let recorder = Recorder()
        let devices = try await api(
            body: """
            {"devices":[{"id":"0123456789abcdef","label":"Mitch's iPad","created_at":"2026-10-19T15:00:00.000Z",
              "expires_at":"2026-10-26T15:00:00.000Z","current":true},
              {"id":"fedcba9876543210","label":null,"created_at":"2026-10-18T15:00:00Z","expires_at":"2026-10-25T15:00:00Z","current":false}]}
            """,
            recorder: recorder
        ).devices(Self.session)
        #expect(devices.map(\.current) == [true, false])
        #expect(devices[0].label == "Mitch's iPad")
        #expect(devices[0].addedDate != nil && devices[1].addedDate != nil)
        #expect(await recorder.requests.last?.url?.path() == "/api/devices")

        let hex = String(repeating: "ab", count: 32)
        let code = try await api(status: 201, body: #"{"code":"\#(hex)","expiresAt":"2026-10-19T15:10:00.000Z"}"#, recorder: recorder)
            .issueDeviceCode(Self.session)
        #expect(code.code == hex && code.server == Self.server)
        #expect(code.link == EnrollLink(server: Self.server, code: hex))
        #expect(await recorder.requests.last?.httpMethod == "POST")
        #expect(await recorder.requests.last?.url?.path() == "/api/devices/codes")

        try await api(body: #"{"revoked":true}"#, recorder: recorder).revokeDevice(Self.session, id: "fedcba9876543210")
        #expect(await recorder.requests.last?.url?.path() == "/api/devices/fedcba9876543210/revoke")
    }

    @Test("An enroll link round-trips; anything else is refused")
    func enrollLink() throws {
        let hex = String(repeating: "0f", count: 32)
        let link = EnrollLink(server: URL(string: "http://mac-mini.tail1234.ts.net:5173")!, code: hex)
        #expect(link.url.absoluteString.hasPrefix("devys://enroll?server=http%3A%2F%2Fmac-mini"))
        #expect(EnrollLink(url: link.url) == link)
        let upper = try #require(URL(string: "devys://enroll?server=https%3A%2F%2Fdevys.test&code=\(hex.uppercased())"))
        #expect(EnrollLink(url: upper)?.code == hex)
        let refused = [
            "devys://enroll?server=https%3A%2F%2Fdevys.test&code=abc",
            "devys://enroll?server=ftp%3A%2F%2Fdevys.test&code=\(hex)",
            "devys://other?server=https%3A%2F%2Fdevys.test&code=\(hex)",
            "https://enroll?server=https%3A%2F%2Fdevys.test&code=\(hex)",
            "devys://enroll?code=\(hex)"
        ]
        for raw in refused { #expect(EnrollLink(url: URL(string: raw)!) == nil, "\(raw)") }
    }

    @Test("Roles decode; a new business sends its brief and starting team; editing PUTs name and brief")
    func businesses() async throws {
        let recorder = Recorder()
        let roles = try await api(
            body: """
            {"roles":[{"id":"engineering","name":"Engineering","summary":"Builds.","responsibilities":"Owns the code.",
              "capabilities":["read","write","run"]}]}
            """,
            recorder: recorder
        ).roles(Self.session)
        #expect(roles == [RoleTemplate(id: "engineering", name: "Engineering", summary: "Builds.", responsibilities: "Owns the code.", capabilities: ["read", "write", "run"])])

        let business = try await api(
            status: 201,
            body: #"{"business":{"id":"b2","name":"Globex","look":null,"brief":"Notes app"},"operations":{},"team":[]}"#,
            recorder: recorder
        ).createBusiness(Self.session, NewBusiness(name: "Globex", brief: "Notes app", team: ["engineering", "growth"]))
        #expect(business.brief == "Notes app")
        var (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses" && request.httpMethod == "POST")
        #expect(body["brief"] as? String == "Notes app")
        #expect(body["team"] as? [String] == ["engineering", "growth"])

        let saved = try await api(body: #"{"business":{"id":"b2","name":"Globex","brief":"Shared notes"}}"#, recorder: recorder)
            .updateBusiness(Self.session, id: "b2", name: nil, brief: "Shared notes")
        #expect(saved.brief == "Shared notes")
        (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "PUT" && request.url?.path() == "/api/businesses/b2")
        #expect(body["brief"] as? String == "Shared notes" && body["name"] == nil)
    }

    @Test("Hiring posts the template and details and decodes the employee with its template")
    func hire() async throws {
        let recorder = Recorder()
        let employee = try await api(
            status: 201,
            body: #"{"id":"e9","business_id":"b1","name":"Growth","role":"Grows it.","model":"gpt-6.1-sol","template":"growth","paused":false,"look":null}"#,
            recorder: recorder
        ).hire(Self.session, businessID: "b1", Hire(template: "growth", name: "Growth", responsibilities: "Grows it.", model: "gpt-6.1-sol"))
        #expect(employee.template == "growth" && employee.role == "Grows it.")
        let (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/employees" && request.httpMethod == "POST")
        #expect(body["template"] as? String == "growth")
        #expect(body["responsibilities"] as? String == "Grows it.")
        #expect(body["model"] as? String == "gpt-6.1-sol")
    }

    @Test("Profile edits PUT only what changed; retiring names the successor")
    func profileAndRetire() async throws {
        let recorder = Recorder()
        try await api(body: #"{"name":"Ada"}"#, recorder: recorder).updateProfile(Self.session, Self.scope, ProfileChange(name: "Ada"))
        var (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "PUT" && request.url?.path() == "/api/businesses/b1/employees/e1/profile")
        #expect(body["name"] as? String == "Ada" && body["responsibilities"] == nil)

        let successor = try await api(body: #"{"retired":true,"reassignedTo":"ops"}"#, recorder: recorder)
            .retire(Self.session, Self.scope, reassignTo: "ops")
        #expect(successor == "ops")
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/employees/e1/retire")
        #expect(body["reassignTo"] as? String == "ops")
        await #expect(throws: DevysHTTPError.rejected(status: 409, message: "The Head of Operations can't be retired")) {
            try await api(status: 409, body: "The Head of Operations can't be retired", recorder: recorder)
                .retire(Self.session, Self.scope, reassignTo: "e2")
        }
    }

    @Test("Spaces carry a lead; creating and changing one send only what was given")
    func spaces() async throws {
        let recorder = Recorder()
        let spaces = try await api(
            body: #"{"spaces":[{"id":"s1","name":"Launch","purpose":"Ship it","lead_employee_id":"ops","items":[]}]}"#,
            recorder: recorder
        ).spaces(Self.session, businessID: "b1")
        #expect(spaces.first?.leadEmployeeID == "ops")

        try await api(status: 201, body: "{}", recorder: recorder)
            .createSpace(Self.session, businessID: "b1", NewSpace(name: "Launch", purpose: "Ship it", lead: "growth"))
        var (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/spaces")
        #expect(body["purpose"] as? String == "Ship it" && body["lead"] as? String == "growth")

        try await api(body: #"{"updated":true}"#, recorder: recorder)
            .updateSpace(Self.session, businessID: "b1", spaceID: "s1", SpaceChange(lead: "growth"))
        (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "PUT" && request.url?.path() == "/api/businesses/b1/spaces/s1")
        #expect(body["lead"] as? String == "growth" && body["name"] == nil)
    }

    @Test("Work: create with space, reassign at a revision, clear a due date")
    func work() async throws {
        let recorder = Recorder()
        let commitment = """
        {"id":"c1","owner_employee_id":"growth","title":"PR inquiry","objective":"","next_action":"","wait_condition":null,
         "due_at":null,"state":"ready","evidence":[],"revision":4,"taken_over_by":null,"updated_at":"2026-10-19T15:00:00.000Z"}
        """
        let created = try await api(status: 201, body: commitment, recorder: recorder).createCommitment(
            Self.session,
            businessID: "b1",
            NewTask(title: "PR inquiry", owner: "growth", objective: "Ten units", dueAt: "2026-10-20T15:00:00Z", spaceId: "s1")
        )
        #expect(created.revision == 4)
        var (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/work" && request.httpMethod == "POST")
        #expect(body["spaceId"] as? String == "s1" && body["dueAt"] as? String == "2026-10-20T15:00:00Z" && body["objective"] as? String == "Ten units")

        _ = try await api(body: commitment, recorder: recorder)
            .updateCommitment(Self.session, businessID: "b1", id: "c1", .reassign(created, to: "ops"))
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/work/c1")
        #expect(body["expectedRevision"] as? Int == 4 && body["owner"] as? String == "ops" && body["state"] as? String == "ready")
        #expect(body.keys.sorted() == ["expectedRevision", "owner", "state"])

        _ = try await api(body: commitment, recorder: recorder)
            .updateCommitment(Self.session, businessID: "b1", id: "c1", CommitmentChange(expectedRevision: 4, waitCondition: .set("Supplier"), dueAt: .clear))
        (_, body) = try await sent(recorder)
        #expect(body["waitCondition"] as? String == "Supplier")
        #expect(body["dueAt"] is NSNull)
    }

    @Test("Google Drive's connection state decodes and ignores the file list")
    func google() async throws {
        let recorder = Recorder()
        let connection = try await api(body: #"{"configured":true,"connected":false,"files":[{"id":"x"}]}"#, recorder: recorder)
            .googleConnection(Self.session, businessID: "b1")
        #expect(connection == GoogleConnection(configured: true, connected: false))
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/connections/google")
    }
}
