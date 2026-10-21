import DevysClient
import Foundation
import Testing

@Suite("Devices, team, projects and work API")
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

    @Test("Projects decode their goal, deadline, budget, lead, team and kept records")
    func projects() async throws {
        let recorder = Recorder()
        let projects = try await api(
            body: """
            {"projects":[{"id":"p1","name":"Launch","goal":"First customers","deadline":"2026-11-30",
             "budget":{"cents":50000,"currency":"USD"},"lead_employee_id":"ops","member_ids":["growth"],
             "items":[{"id":"i1","ref":"devys:documents/artifact/a1"},{"id":"i2","ref":"devys:documents/file/%2Fb%2Fplan.md"}]},
             {"id":"p2","name":"Hiring","goal":null,"deadline":null,"budget":null,"lead_employee_id":null,"member_ids":[],"items":[]}]}
            """,
            recorder: recorder
        ).projects(Self.session, businessID: "b1")
        #expect(projects.first == Project(
            id: "p1",
            name: "Launch",
            goal: "First customers",
            deadline: "2026-11-30",
            budget: Budget(cents: 50_000),
            leadEmployeeID: "ops",
            memberIDs: ["growth"],
            items: [ProjectItem(id: "i1", ref: .artifact("a1")), ProjectItem(id: "i2", ref: .file("/b/plan.md"))]
        ))
        #expect(projects.first?.keeps(.file("/b/plan.md"))?.id == "i2" && projects.first?.keeps(.file("a1")) == nil)
        #expect(projects.last?.budget == nil && projects.last?.goal == nil)
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/projects")
    }

    @Test("Creating and editing a project send every field; nil clears a goal, deadline or budget")
    func projectChanges() async throws {
        let recorder = Recorder()
        let created = try await api(status: 201, body: #"{"id":"p3","name":"Launch","goal":null,"deadline":null,"budget":null,"lead_employee_id":"ops","member_ids":[],"items":[]}"#, recorder: recorder)
            .createProject(Self.session, businessID: "b1", ProjectChange(name: "Launch", deadline: "2026-11-30", budget: Budget(cents: 1_200), members: ["growth"]))
        #expect(created.id == "p3")
        var (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "POST" && request.url?.path() == "/api/businesses/b1/projects")
        #expect(body["goal"] is NSNull && body["deadline"] as? String == "2026-11-30" && body["lead"] == nil)
        #expect((body["budget"] as? [String: Any])?["cents"] as? Int == 1_200 && body["members"] as? [String] == ["growth"])

        try await api(body: "{}", recorder: recorder)
            .updateProject(Self.session, businessID: "b1", projectID: "p3", ProjectChange(name: "Launch", goal: "Ship", lead: "growth"))
        (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "PUT" && request.url?.path() == "/api/businesses/b1/projects/p3")
        #expect(body["goal"] as? String == "Ship" && body["lead"] as? String == "growth" && body["budget"] is NSNull)

        try await api(body: "{}", recorder: recorder).addToProject(Self.session, businessID: "b1", projectID: "p3", ref: .artifact("a1"))
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/projects/p3/items" && body.keys.sorted() == ["ref"] && body["ref"] as? String == "devys:documents/artifact/a1")

        try await api(body: #"{"removed":true}"#, recorder: recorder).removeFromProject(Self.session, businessID: "b1", projectID: "p3", itemID: "i1")
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/projects/p3/items/i1/remove")
    }

    @Test("Apps list with their kind, skills, install and pin state; installing, removing and pinning post to the app")
    func apps() async throws {
        let recorder = Recorder()
        let apps = try await api(
            body: """
            {"apps":[{"id":"documents","name":"Documents","icon":"file-text","summary":"Pages and files","kind":"business","status":"available",
              "skills":[{"name":"pages","description":"Publish a page"}],"installed":true,"pinned":true,"visible":true},
             {"id":"memory","name":"Memory","icon":"brain","summary":"What employees remember","kind":"system","status":"available",
              "skills":[],"installed":true,"pinned":false,"visible":false},
             {"id":"mail","name":"Mail","icon":"mail","summary":"Mailboxes","kind":"business","status":"coming","skills":[],"installed":false,"pinned":false,"visible":false}]}
            """,
            recorder: recorder
        ).apps(Self.session, businessID: "b1")
        #expect(apps.map(\.id) == ["documents", "memory", "mail"] && apps.last?.status == .coming && apps.first?.visible == true)
        #expect(apps.first?.skills == [AppEntry.Skill(name: "pages", description: "Publish a page")])
        #expect(apps.map(\.kind) == [.business, .system, .business] && apps[1].installed && !apps[1].pinned)

        try await api(body: "{}", recorder: recorder).installApp(Self.session, businessID: "b1", appID: "code", install: false)
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/apps/code/uninstall")
        try await api(body: "{}", recorder: recorder).pinApp(Self.session, businessID: "b1", appID: "code", pinned: false)
        let (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/apps/code/pin" && body["pinned"] as? Bool == false)
    }

    @Test("Home decodes what needs the owner and work at a glance")
    func home() async throws {
        let recorder = Recorder()
        let home = try await api(
            body: """
            {"needsYou":[{"kind":"decision","id":"d1","title":"Buy domain","employeeId":"growth","workId":"c1","projectId":"p1"},
             {"kind":"work","id":"c2","title":"Decide pricing","employeeId":null,"workId":"c2","projectId":null}],
             "glance":{"moving":[{"id":"c3","title":"Fix sitemap","employeeId":"engineering","projectId":"p1","state":"in_progress",
              "waitCondition":null,"dueAt":null,"updatedAt":"2026-10-20T10:00:00.000Z"}],"stuck":[],"spentCents":3800}}
            """,
            recorder: recorder
        ).home(Self.session, businessID: "b1")
        #expect(home.needsYou.first == NeedsYouItem(kind: .decision, id: "d1", title: "Buy domain", employeeID: "growth", workID: "c1", projectID: "p1"))
        #expect(home.needsYou.last?.employeeID == nil && home.needsYou.last?.kind == .work)
        #expect(home.glance.moving.first?.state == .inProgress && home.glance.moving.first?.projectID == "p1")
        #expect(home.glance.spentCents == 3_800 && !home.isEmpty)
        #expect(Home().isEmpty)
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/home")
    }

    @Test("Work: create in a project, reassign at a revision, clear a due date")
    func work() async throws {
        let recorder = Recorder()
        let workItem = """
        {"id":"c1","owner_employee_id":"growth","title":"PR inquiry","objective":"","next_action":"","wait_condition":null,
         "due_at":null,"state":"ready","evidence":[],"revision":4,"taken_over_by":null,"project_id":"p1","updated_at":"2026-10-19T15:00:00.000Z"}
        """
        let created = try await api(status: 201, body: workItem, recorder: recorder).createWorkItem(
            Self.session,
            businessID: "b1",
            NewWorkItem(title: "PR inquiry", owner: "growth", objective: "Ten units", dueAt: "2026-10-20T15:00:00Z", projectId: "p1")
        )
        #expect(created.revision == 4 && created.projectID == "p1")
        var (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/work" && request.httpMethod == "POST")
        #expect(body["projectId"] as? String == "p1" && body["dueAt"] as? String == "2026-10-20T15:00:00Z" && body["objective"] as? String == "Ten units")

        _ = try await api(body: workItem, recorder: recorder)
            .updateWorkItem(Self.session, businessID: "b1", id: "c1", .reassign(created, to: "ops"))
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/work/c1")
        #expect(body["expectedRevision"] as? Int == 4 && body["owner"] as? String == "ops" && body["state"] as? String == "ready")
        #expect(body.keys.sorted() == ["expectedRevision", "owner", "state"])

        _ = try await api(body: workItem, recorder: recorder)
            .updateWorkItem(Self.session, businessID: "b1", id: "c1", WorkItemChange(expectedRevision: 4, waitCondition: .set("Supplier"), dueAt: .clear))
        (_, body) = try await sent(recorder)
        #expect(body["waitCondition"] as? String == "Supplier")
        #expect(body["dueAt"] is NSNull)

        let listed = try await api(body: #"{"workItems":[\#(workItem)]}"#, recorder: recorder).work(Self.session, businessID: "b1")
        #expect(listed.map(\.id) == ["c1"])
    }

    @Test("A work item's decisions are asked for by workItem and name it")
    func workDecisions() async throws {
        let recorder = Recorder()
        let page = """
        {"decisions":[{"id":"d1","employee_id":"growth","capability":"email.send","input":{},"work_item_id":"c1","status":"approved",
         "requested_at":"2026-10-19T15:00:00.000Z","expires_at":"2026-10-20T15:00:00.000Z"}]}
        """
        let decisions = try await api(body: page, recorder: recorder).decisions(Self.session, businessID: "b1", workItemID: "c1")
        #expect(decisions.first?.workItemID == "c1")
        let url = try #require(await recorder.requests.last?.url)
        #expect(url.path() == "/api/businesses/b1/decisions" && url.query() == "workItem=c1")
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
