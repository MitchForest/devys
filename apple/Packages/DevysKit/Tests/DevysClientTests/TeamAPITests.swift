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

    @Test("Signing in: the owner's key, asking to join with a chosen token's hash, its status, and the answer")
    func signingIn() async throws {
        let recorder = Recorder()
        let owner = OwnerFile(server: Self.server, key: String(repeating: "a", count: 64))
        let session = try await api(body: #"{"session_token":"abc","expires_in_seconds":1}"#, recorder: recorder)
            .localSession(owner, name: "Sam Rivera", label: "Sam's Mac mini")
        #expect(session == DeviceSession(server: Self.server, token: "abc"))
        var (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/local/session" && request.httpMethod == "POST")
        #expect(body["key"] as? String == owner.key && body["name"] as? String == "Sam Rivera" && body["label"] as? String == "Sam's Mac mini")

        let hash = String(repeating: "b", count: 64)
        let asked = try await api(status: 201, body: #"{"id":"j1","name":"iPad","match":["🦊","🌵"],"expires_at":"2026-10-19T15:10:00.000Z"}"#, recorder: recorder)
            .askToJoin(server: Self.server, name: "iPad", sessionHash: hash, publicKey: "key")
        #expect(asked == JoinRequest(id: "j1", name: "iPad", match: ["🦊", "🌵"]))
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/joins" && request.value(forHTTPHeaderField: "authorization") == nil)
        #expect(body["session_hash"] as? String == hash && body["public_key"] as? String == "key")

        let status = try await api(body: #"{"status":"pending"}"#, recorder: recorder).joinStatus(server: Self.server, id: "j1", token: "tok")
        #expect(status == "pending")
        (request, _) = try await sent(recorder)
        #expect(request.url?.path() == "/api/joins/j1" && request.value(forHTTPHeaderField: "authorization") == "Bearer tok")

        let key = try await api(body: #"{"key":null}"#, recorder: recorder).answerJoin(Self.session, id: "j1", allow: false)
        #expect(key == nil)
        (request, _) = try await sent(recorder)
        #expect(request.url?.path() == "/api/joins/j1/deny" && request.httpMethod == "POST")

        let link = try await api(status: 201, body: #"{"token":"\#(hash)","expires_at":"2026-10-19T15:10:00.000Z"}"#, recorder: recorder)
            .signInLink(Self.session)
        #expect(link.absoluteString == "https://devys.test/#signin=\(hash)")
    }

    @Test("Renaming the signed-in person puts their new name and reads the account back")
    func rename() async throws {
        let recorder = Recorder()
        let account = try await api(
            body: #"{"person":{"id":"p1","display_name":"Sam Rivera"},"businesses":[]}"#,
            recorder: recorder
        ).rename(Self.session, "Sam Rivera")
        let (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "PUT" && request.url?.path() == "/api/me")
        #expect(body["display_name"] as? String == "Sam Rivera")
        #expect(account.person.displayName == "Sam Rivera")
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

        try await api(body: #"{"revoked":true}"#, recorder: recorder).revokeDevice(Self.session, id: "fedcba9876543210")
        #expect(await recorder.requests.last?.url?.path() == "/api/devices/fedcba9876543210/revoke")
    }

    @Test("A connect link round-trips; anything else is refused")
    func connectLink() throws {
        let mac = FoundMac(name: "Sam's Mac mini", server: URL(string: "http://mac-mini.tail1234.ts.net:8787")!)
        let link = ConnectLink(mac: mac)
        #expect(link.url.absoluteString.hasPrefix("devys://connect?server=http%3A%2F%2Fmac-mini"))
        #expect(ConnectLink(url: link.url) == link)
        #expect(ConnectLink(url: URL(string: "devys://connect?server=https%3A%2F%2Fdevys.test")!)?.mac.name == "your Mac")
        let refused = [
            "devys://connect?server=ftp%3A%2F%2Fdevys.test",
            "devys://other?server=https%3A%2F%2Fdevys.test",
            "https://connect?server=https%3A%2F%2Fdevys.test",
            "devys://connect?name=Mini"
        ]
        for raw in refused { #expect(ConnectLink(url: URL(string: raw)!) == nil, "\(raw)") }
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
            body: #"{"id":"e9","business_id":"b1","name":"Growth","responsibilities":"Grows it.","model":"gpt-6.1-sol","template":"growth","paused":false,"look":null}"#,
            recorder: recorder
        ).hire(Self.session, businessID: "b1", Hire(template: "growth", name: "Growth", responsibilities: "Grows it.", model: "gpt-6.1-sol"))
        #expect(employee.template == "growth" && employee.responsibilities == "Grows it.")
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

        let successor = try await api(body: #"{"retired":true,"reassigned_to":"ops"}"#, recorder: recorder)
            .retire(Self.session, Self.scope, reassignTo: "ops")
        #expect(successor == "ops")
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/employees/e1/retire")
        #expect(body["reassign_to"] as? String == "ops")
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
        #expect(projects.first?.items.map(\.ref) == [.artifact("a1"), .file("/b/plan.md")])
        #expect(projects.last?.budget == nil && projects.last?.goal == nil)
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/projects")
    }

    @Test("Creating a project sends every field; keeping and removing a record post to the project")
    func projectChanges() async throws {
        let recorder = Recorder()
        let created = try await api(status: 201, body: #"{"id":"p3","name":"Launch","goal":null,"deadline":null,"budget":null,"lead_employee_id":"ops","member_ids":[],"items":[]}"#, recorder: recorder)
            .createProject(Self.session, businessID: "b1", ProjectChange(name: "Launch", deadline: "2026-11-30", budget: Budget(cents: 1_200), members: ["growth"]))
        #expect(created.id == "p3")
        var (request, body) = try await sent(recorder)
        #expect(request.httpMethod == "POST" && request.url?.path() == "/api/businesses/b1/projects")
        #expect(body["goal"] is NSNull && body["deadline"] as? String == "2026-11-30" && body["lead"] == nil)
        #expect((body["budget"] as? [String: Any])?["cents"] as? Int == 1_200 && body["members"] as? [String] == ["growth"])

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
            {"apps":[{"id":"documents","name":"Documents","icon":"file-text","summary":"Pages and files","kind":"business","records":[],
              "skills":[{"name":"pages","description":"Publish a page"}],"installed":true,"pinned":true,"visible":true},
             {"id":"memory","name":"Memory","icon":"brain","summary":"What employees remember","kind":"system","records":[],
              "skills":[],"installed":true,"pinned":false,"visible":false},
             {"id":"code","name":"Code","icon":"code","summary":"Repositories","kind":"business","records":[],"skills":[],"installed":false,"pinned":false,"visible":false}]}
            """,
            recorder: recorder
        ).apps(Self.session, businessID: "b1")
        #expect(apps.map(\.id) == ["documents", "memory", "code"] && apps.last?.installed == false && apps.first?.visible == true)
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
            {"needs_you":[{"kind":"decision","id":"d1","title":"Buy domain","employee_id":"growth","work_id":"c1","project_id":"p1",
              "capability":"domainBuy","input":{"domain":"acme.com"},"work_item_id":"c1","status":"pending",
              "requested_at":"2026-10-20T10:00:00.000Z","expires_at":"2026-10-21T10:00:00.000Z"},
             {"kind":"work","id":"c2","title":"Decide pricing","employee_id":null,"work_id":"c2","project_id":null}],
             "glance":{"moving":[{"id":"c3","title":"Fix sitemap","employee_id":"engineering","project_id":"p1","state":"in_progress",
              "wait_condition":null,"due_at":null,"updated_at":"2026-10-20T10:00:00.000Z"}],"stuck":[],"spent_cents":null}}
            """,
            recorder: recorder
        ).home(Self.session, businessID: "b1")
        let decision = Decision(
            id: "d1", employeeID: "growth", capability: "domainBuy", input: .object(["domain": .string("acme.com")]), workItemID: "c1",
            requestedAt: "2026-10-20T10:00:00.000Z", expiresAt: "2026-10-21T10:00:00.000Z"
        )
        #expect(home.needsYou.first == NeedsYouItem(decision, title: "Buy domain", projectID: "p1"))
        #expect(home.decisions == [decision])
        #expect(home.needsYou.last?.employeeID == nil && home.needsYou.last?.kind == .work && home.needsYou.last?.decision == nil)
        #expect(home.glance.moving.first?.state == .inProgress && home.glance.moving.first?.projectID == "p1")
        #expect(!home.isEmpty)
        #expect(Home().isEmpty)
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b1/home")
    }

    @Test("Work: create in a project, reassign at a revision, clear a due date")
    func work() async throws {
        let recorder = Recorder()
        let workItem = """
        {"id":"c1","owner_employee_id":"growth","title":"PR inquiry","objective":"","next_action":"","wait_condition":null,
         "due_at":null,"state":"ready","evidence":[],"steps":[],"results":[],"revision":4,"taken_over_by":null,"project_id":"p1","updated_at":"2026-10-19T15:00:00.000Z"}
        """
        let created = try await api(status: 201, body: workItem, recorder: recorder).createWorkItem(
            Self.session,
            businessID: "b1",
            NewWorkItem(title: "PR inquiry", owner: "growth", objective: "Ten units", dueAt: "2026-10-20T15:00:00Z", projectID: "p1")
        )
        #expect(created.revision == 4 && created.projectID == "p1")
        var (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/work" && request.httpMethod == "POST")
        #expect(body["project_id"] as? String == "p1" && body["due_at"] as? String == "2026-10-20T15:00:00Z" && body["objective"] as? String == "Ten units")

        _ = try await api(body: workItem, recorder: recorder)
            .updateWorkItem(Self.session, businessID: "b1", id: "c1", .reassign(created, to: "ops"))
        (request, body) = try await sent(recorder)
        #expect(request.url?.path() == "/api/businesses/b1/work/c1")
        #expect(body["expected_revision"] as? Int == 4 && body["owner"] as? String == "ops" && body["state"] as? String == "ready")
        #expect(body.keys.sorted() == ["expected_revision", "owner", "state"])

        _ = try await api(body: workItem, recorder: recorder)
            .updateWorkItem(Self.session, businessID: "b1", id: "c1", WorkItemChange(expectedRevision: 4, waitCondition: .set("Supplier"), dueAt: .clear))
        (_, body) = try await sent(recorder)
        #expect(body["wait_condition"] as? String == "Supplier")
        #expect(body["due_at"] is NSNull)

        let listed = try await api(body: #"{"work_items":[\#(workItem)]}"#, recorder: recorder).work(Self.session, businessID: "b1")
        #expect(listed.map(\.id) == ["c1"])
    }

    @Test("A work item's decisions are asked for by work_item and name it")
    func workDecisions() async throws {
        let recorder = Recorder()
        let page = """
        {"decisions":[{"id":"d1","kind":"decision","employee_id":"growth","capability":"email.send","input":{},"work_item_id":"c1","status":"approved",
         "requested_at":"2026-10-19T15:00:00.000Z","expires_at":"2026-10-20T15:00:00.000Z","signed_by":null}]}
        """
        let decisions = try await api(body: page, recorder: recorder).decisions(Self.session, businessID: "b1", workItemID: "c1")
        #expect(decisions.first?.workItemID == "c1")
        let url = try #require(await recorder.requests.last?.url)
        #expect(url.path() == "/api/businesses/b1/decisions" && url.query() == "work_item=c1")
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
