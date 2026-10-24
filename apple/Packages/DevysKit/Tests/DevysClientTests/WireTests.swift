import DevysClient
import Foundation
import Testing

/// The server's golden responses (`bun run wire:write`, from tests/wire.workers.test.ts), each read
/// through the client call that reads that route, so server drift fails this suite.
@Suite("Wire contract")
struct WireTests {
    private typealias Read = @Sendable (DevysHTTPClient, DeviceSession) async throws -> any Sendable

    private static let session = DeviceSession(server: URL(string: "https://devys.test")!, token: "tok")
    private static let scope = EmployeeScope(businessID: "b1", employeeID: "e1")

    /// Every golden file and the call that reads it.
    private static let reads: [String: Read] = [
        "access": { try await $0.access($1, scope) },
        "app-changed": { try await $0.acceptApp($1, businessID: "b1", appID: "ledger", AppAcceptance(lines: ["ledger_list_entries": .own], employees: ["e1"])) },
        "app-review": { try await $0.appReview($1, businessID: "b1", appID: "ledger") },
        "app-search": { try await $0.searchApps($1, businessID: "b1", query: "books") },
        "apps": { try await $0.apps($1, businessID: "b1") },
        "apps-listed": { try await $0.listedApps($1, businessID: "b1") },
        "browser": { try await $0.browserStatus($1, businessID: "b1") },
        "browser-front": { try await $0.browserFront($1, businessID: "b1") },
        "business-created": { try await $0.createBusiness($1, NewBusiness(name: "Acme Roofing")) },
        "business-updated": { try await $0.updateBusiness($1, id: "b1", name: nil, brief: "Roof repairs.") },
        "business": { try await $0.business($1, id: "b1") },
        "coded-work": { try await $0.codingWork($1, businessID: "b1") },
        "connecting": { try await $0.connectApp($1, businessID: "b1", appID: "acmebooks") },
        "coding-sessions": { try await $0.codingSessions($1, businessID: "b1", workID: "w1") },
        "conversation-work": { try await $0.conversation($1, businessID: "b1", key: .work("w1")) },
        "conversation": { try await $0.conversation($1, businessID: "b1", key: .direct("e1")) },
        "conversations": { try await $0.conversations($1, businessID: "b1") },
        "decisions": { try await $0.decisions($1, businessID: "b1", workItemID: "w1") },
        "device-link": { try await $0.signInLink($1) },
        "device-key": { try await $0.enrollKey($1, publicKey: Data(repeating: 4, count: 65)) },
        "device-keys": { try await $0.deviceKeys($1) },
        "devices": { try await $0.devices($1) },
        "diff": { try await $0.sessionDiff($1, businessID: "b1", workID: "w1", sessionID: "s1") },
        "employee": { try await $0.hire($1, businessID: "b1", Hire(template: "engineering", name: "Ada")) },
        "file-text": { try await $0.fileText($1, businessID: "b1", path: "/brief.md") },
        "files": { try await $0.files($1, businessID: "b1", path: nil).entries },
        "google": { try await $0.googleConnection($1, businessID: "b1") },
        "hello": { try await $0.hello(server: $1.server) },
        "join": { try await $0.askToJoin(server: $1.server, name: "iPhone", sessionHash: "h", publicKey: nil) },
        "join-answered": { try await $0.answerJoin($1, id: "j1", allow: true) },
        "joins": { try await $0.joins($1) },
        "home": { try await $0.home($1, businessID: "b1") },
        "look": { _, _ in try Wire.decoder().decode(LookChanged.self, from: golden("look")) },
        "me": { try await $0.account($1) },
        "memory": { try await $0.memory($1, businessID: "b1") },
        "models": { try await $0.models($1) },
        "posted": { try await $0.postMessage($1, businessID: "b1", key: .direct("e1"), NewMessage(id: "m1", text: "Hi")) },
        "project-item": { _, _ in try Wire.decoder().decode(ProjectItem.self, from: golden("project-item")) },
        "project": { try await $0.createProject($1, businessID: "b1", ProjectChange(name: "Spring launch")) },
        "projects": { try await $0.projects($1, businessID: "b1") },
        "roles": { try await $0.roles($1) },
        "routine": { try await $0.setRoutinePaused($1, businessID: "b1", id: "r1", paused: true) },
        "routines": { try await $0.routines($1, businessID: "b1", employeeID: "e1") },
        "secrets": { try await $0.addSecret($1, businessID: "b1", NewSecret(name: "STRIPE_KEY", value: .secret("sk_test"))) },
        "sidebar-mark": { try await $0.markSidebar($1, businessID: "b1", key: .direct("e1"), SidebarMark(pinned: true)) },
        "screenshot": { try await $0.browserPicture($1, businessID: "b1") },
        "status": { try await $0.status($1, scope) },
        "steps": { try await $0.steps($1, businessID: "b1", key: .direct("e1"), messageID: "m1") },
        "terminals": { try await $0.terminals($1, businessID: "b1") },
        "transcript": { try await $0.sessionTranscript($1, businessID: "b1", workID: "w1", sessionID: "s1") },
        "work-item-updated": { try await $0.updateWorkItem($1, businessID: "b1", id: "w1", WorkItemChange(expectedRevision: 1)) },
        "work-item": { try await $0.createWorkItem($1, businessID: "b1", NewWorkItem(title: "Publish", owner: "e1")) },
        "work": { try await $0.work($1, businessID: "b1") }
    ]

    /// What `POST …/look` answers; the client sends looks and never reads this body.
    private struct LookChanged: Decodable { let look: Look? }

    static func golden(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/wire"))
        return try Data(contentsOf: url)
    }

    private static func answering(_ name: String) throws -> DevysHTTPClient {
        let body = try golden(name)
        return DevysHTTPClient { request in
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw URLError(.badURL)
            }
            return (body, response)
        }
    }

    @Test("Every golden file has a reader here: a new route's response fails until the client reads it")
    func everyFileIsRead() throws {
        let folder = try #require(Bundle.module.resourceURL).appending(path: "Fixtures/wire")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
        #expect(Set(files) == Set(Self.reads.keys))
    }

    @Test("Each golden response decodes through the call that reads it", arguments: reads.keys.sorted())
    func decodes(_ name: String) async throws {
        let read = try #require(Self.reads[name])
        _ = try await read(try Self.answering(name), Self.session)
    }

    @Test("The secure entry sheet sends a value or a card as the server takes it, and never prints one")
    func newSecret() throws {
        let object = { (secret: NewSecret) throws -> [String: Any] in
            try #require(JSONSerialization.jsonObject(with: Wire.encoder().encode(secret)) as? [String: Any])
        }
        let key = NewSecret(name: "STRIPE_KEY", value: .secret("sk_live_hidden"))
        #expect(try object(key) as NSDictionary == ["name": "STRIPE_KEY", "kind": "secret", "value": "sk_live_hidden"])
        let card = NewSecret(name: "RAMP_CARD", value: .card(CardEntry(number: "4242424242424242", expiry: "04/31", cvc: nil, name: "Sam", postal: "94107")))
        #expect(try object(card) as NSDictionary == [
            "name": "RAMP_CARD", "kind": "spend",
            "card": ["number": "4242424242424242", "expiry": "04/31", "name": "Sam", "postal": "94107"]
        ])
        #expect(!"\(key)".contains("sk_live") && !String(reflecting: card).contains("4242"))
        #expect(NewSecret.isName("RAMP_CARD") && !NewSecret.isName("ramp") && !NewSecret.isName("1KEY"))
    }

    @Test("What a running employee is doing, how a reply was worked out and its steps decode in the owner's words")
    func activity() async throws {
        let status = try await Self.answering("status").status(Self.session, EmployeeScope(businessID: "b1", employeeID: "e1"))
        #expect(status.state.run?.doing == "Opening example.com")
        let direct = try await Self.answering("conversation").conversation(Self.session, businessID: "b1", key: .direct("e1"))
        #expect(direct.messages.compactMap(\.worked) == [Worked(ms: 80_000, steps: 2)])
        let steps = try await Self.answering("steps").steps(Self.session, businessID: "b1", key: .direct("e1"), messageID: "m1")
        #expect(steps == ["Searching the app directory", "Opening example.com"])
    }

    @Test("A work item's steps and results, its card where it was created and Home's progress decode in the web's words")
    func workProgress() async throws {
        let work = try await Self.answering("work").work(Self.session, businessID: "b1")
        let site = try #require(work.first { !$0.steps.isEmpty })
        #expect(site.steps.map(\.state) == [.done, .doing, .todo, .blocked])
        #expect(site.results.map(\.text) == [
            "Preview https://preview.acme.test ✓",
            "Booking form · test booking received ✓",
            "Calendar sync ?",
            "Pages · 3"
        ])
        #expect(WorkStep.progress(site.steps) == "1 of 4 · Blocked: Connect the calendar")
        let thread = try await Self.answering("conversation-work").conversation(Self.session, businessID: "b1", key: .work("w1"))
        #expect(!thread.messages.contains { $0.kind == .card }, "a thread pins its card; no card message in it")
        let direct = try await Self.answering("conversation").conversation(Self.session, businessID: "b1", key: .direct("e1"))
        let cards = direct.messages.filter { $0.kind == .card }
        #expect(cards.count == 1 && cards.first?.ref == .workItem(site.id) && cards.first?.isEvent == true)
        let home = try await Self.answering("home").home(Self.session, businessID: "b1")
        #expect(home.glance.moving.first { $0.id == site.id }?.progress == WorkStep.progress(site.steps))
    }

    @Test("Golden values land in the right fields")
    func values() async throws {
        let home = try await Self.answering("home").home(Self.session, businessID: "b1")
        let drive = home.needsYou[7]
        #expect(drive.kind == .decision && drive.workID != nil && drive.projectID != nil)
        #expect(home.decisions.last?.capability == "driveCreate" && home.decisions.last?.input.fields.first?.key == "content")
        #expect(home.decisions[1].capability == "routineActivate" && home.needsYou[1].workID == nil)
        #expect(home.glance.moving.first?.state == .inProgress && home.glance.moving.first?.dueAt != nil)
        // What employees ask with askOwner: an app to connect, a file to choose, an approval of
        // steps with its draft, a card to add, a take over and a spend approval to sign; and a
        // remote app whose sign-in lapsed.
        #expect(home.needsYou.map(\.kind) == [.connect, .decision, .file, .approve, .secret, .takeOver, .approve, .decision, .reconnect])
        #expect(home.decisions[2].request == .file(purpose: "The signed supplier agreement", accept: ["application/pdf"]))
        #expect(home.decisions[3].steps == ["Email the launch plan to orders@supplier.test", "Mark the order placed"])
        #expect(home.decisions[3].preview?.kind == "artifact" && home.decisions[3].previewHash?.count == 64)
        #expect(home.decisions[0].request == .connect(app: "acmebooks", why: "To read and draft the supplier's bills"))
        #expect(home.needsYou[0].app == AppBadge(id: "acmebooks", name: "Acme Books") && home.needsYou[0].title == "Acme Books")
        #expect(home.needsYou[8].app?.name == "Ledger" && home.needsYou[8].app?.logo?.hasPrefix("/api/businesses/") == true && home.needsYou[8].decision == nil)
        #expect(home.decisions[4].request == .secret(name: "RAMP_CARD", why: "The company card, to pay for the domain at Namecheap", spend: true))
        #expect(home.decisions[5].request == .takeOver(reason: "Sign in to the registrar (2FA)", url: "https://www.namecheap.com/myaccount/login/"))
        let spend = try #require(SpendApproval(home.decisions[6], businessID: "b1"))
        #expect(spend.amount == Amount(cents: 1299, currency: "USD") && spend.counterparty == "Namecheap" && spend.renewal == "Renews yearly at $14.99")
        #expect(home.decisions[6].isSpend && !home.decisions[5].isSpend && home.decisions[6].signedBy == nil)
        let review = try await Self.answering("app-review").appReview(Self.session, businessID: "b1", appID: "ledger")
        #expect(review.app.state == .review && review.tools.map(\.line) == [.own, .ask] && review.tools.map(\.title) == ["List entries", "Post entry"])
        let apps = try await Self.answering("apps").apps(Self.session, businessID: "b1")
        #expect(apps.first { $0.id == "ledger" }?.state == .lapsed && apps.first { $0.id == "documents" }?.state == nil)
        let secrets = try await Self.answering("secrets").secrets(Self.session, businessID: "b1")
        #expect(secrets == [SecretEntry(name: "STRIPE_KEY", kind: .secret, addedBy: "00000000-0000-4000-8000-000000000001", addedAt: "2026-01-01T00:00:00.000Z")])
        let keys = try await Self.answering("device-keys").deviceKeys(Self.session)
        #expect(keys.first?.status == .active && keys.first?.current == true && keys.first?.label == "iPhone")

        let proposal = try #require(home.needsYou[1].routine)
        #expect(proposal.state == .proposed && proposal.notify == .always && proposal.projectID != nil)
        #expect(proposal.trigger == .cron(expression: "0 9 * * 1", timezone: "America/Chicago", hours: ActiveHours(start: "08:00", end: "18:00", days: ["mon"])))
        #expect(home.needsYou.last?.routine == nil)

        let routines = try await Self.answering("routines").routines(Self.session, businessID: "b1")
        #expect(routines.first?.trigger == .event(source: "mail", type: "received", filters: ["from": .string("parts@supply.test")]))
        #expect(routines.first?.notify == .whenFound && routines.first?.state == .paused && routines.first?.schedule.hasPrefix("When mail") == true)

        let work = try await Self.answering("work").work(Self.session, businessID: "b1")
        #expect(work.allSatisfy { $0.wakeAt == nil })
        let evidence = try #require(work.last?.evidence.first)
        #expect(evidence.check?.exitCode == 0 && evidence.deploy?.live == true && evidence.recordedAt.hasSuffix("Z"))
        let waiting = try #require(work.first { $0.state == .waiting })
        #expect(waiting.waitCondition == "The supplier confirms the price" && waiting.projectID != nil)

        let detail = try await Self.answering("business").business(Self.session, id: "b1")
        #expect(detail.employees.last?.responsibilities.hasPrefix("Build, fix") == true && detail.employees.last?.look != nil)
        #expect(detail.members.first?.displayName == "Owner" && detail.artifacts.first?.byteLength == 1840)
        #expect(detail.artifacts.first?.latestID == "00000000-0000-4000-8000-000000000006")

        let status = try await Self.answering("status").status(Self.session, Self.scope)
        #expect(status.state.run?.conversation == "work:00000000-0000-4000-8000-000000000072")
        #expect(try await Self.answering("browser-front").browserFront(Self.session, businessID: "b1") == 4242)
        #expect(status.state.inbox.map(\.status) == [.done, .running] && status.state.inbox.first?.receivedAt == 1_800_000_000_000)
        #expect(status.state.outbox.first?.status == .sent)
        let usage = try #require(status.state.usage?.models.values.first)
        #expect(usage.cacheRead == 20_000 && usage.cost.total == 0.0625)

        let catalog = try await Self.answering("models").models(Self.session)
        #expect(catalog.model(catalog.defaults.employee)?.price.cacheRead == 0.2 && catalog.models.first?.typicalTurnUsd == 0.046)

        let sessions = try await Self.answering("coding-sessions").codingSessions(Self.session, businessID: "b1", workID: "w1")
        #expect(sessions.first?.state == .idle && sessions.first?.diffStat.contains("3 files changed") == true && sessions.first?.baseCommit != nil)

        let terminals = try await Self.answering("terminals").terminals(Self.session, businessID: "b1")
        #expect(terminals.first?.codingSessionID != nil)

        let joins = try await Self.answering("joins").joins(Self.session)
        #expect(joins.first?.match == ["🦊", "🌵"] && joins.first?.name == "Wire iPhone")
        let allowed = try await Self.answering("join-answered").answerJoin(Self.session, id: "j1", allow: true)
        #expect(allowed?.status == .pending && allowed?.label == "Wire iPhone")

        let thread = try await Self.answering("conversation-work").conversation(Self.session, businessID: "b1", key: .work("w1"))
        #expect(thread.messages.first?.ref == .workItem("00000000-0000-4000-8000-000000000008") && thread.messages.first?.isEvent == true)

        let direct = try await Self.answering("conversation").conversation(Self.session, businessID: "b1", key: .direct("e1"))
        #expect(direct.messages.last?.replies == ["Ship it", "Wait"] && direct.messages.first?.replies.isEmpty == true)
        #expect(direct.messages.last?.question == "Ship the preview now?" && direct.messages.last?.pickMany == false)
        #expect(direct.messages.first?.question == nil)

        let summaries = try await Self.answering("conversations").conversations(Self.session, businessID: "b1")
        #expect(summaries.map(\.pinned) == [true, false] && summaries.map(\.hidden) == [false, false])
        #expect(summaries.first?.last?.question == "Ship the preview now?")

        let mark = try await Self.answering("sidebar-mark").markSidebar(Self.session, businessID: "b1", key: .direct("e1"), SidebarMark(pinned: true))
        #expect(mark == SidebarMark(pinned: true))

        let listed = try await Self.answering("apps-listed").listedApps(Self.session, businessID: "b1")
        #expect(listed.first == ListedApp(
            app: "https://mcp.ramp.com/mcp", name: "Ramp", description: "Cards, spend and bills", category: "Payments and finance",
            logo: "/api/businesses/00000000-0000-4000-8000-000000000002/apps/listed/ramp/logo"
        ))
        #expect(listed.count == 21 && Set(listed.map(\.category)).count == 6 && !listed.contains { ["Documents", "Code"].contains($0.name) })

        let projects = try await Self.answering("projects").projects(Self.session, businessID: "b1")
        #expect(projects.first?.items.first?.ref == .artifact("00000000-0000-4000-8000-000000000006"))
        #expect(projects.first?.leadEmployeeID != nil && projects.first?.memberIDs.count == 1)
    }

    @Test("Values the server may add later decode as unknown; the page still loads")
    func lenient() throws {
        let decoder = Wire.decoder()
        let session = try decoder.decode(
            CodingSession.self,
            from: Data(#"{"id":"s","provider":"codex","purpose":"build","objective":"o","state":"paused","diff_stat":""}"#.utf8)
        )
        #expect(session.state == .unknown)
        let app = try decoder.decode(
            AppEntry.self,
            from: Data(#"{"id":"mail","name":"Mail","icon":"","summary":"","kind":"remote","records":[],"skills":[],"installed":true,"pinned":true,"visible":true}"#.utf8)
        )
        #expect(app.kind == .unknown)
        let message = try decoder.decode(
            ConversationMessage.self,
            from: Data(#"{"id":"m","author":"system","kind":"event","text":"t","ref":"devys:mail/thread/t1","created_at":"2026-01-01T00:00:00.000Z"}"#.utf8)
        )
        #expect(message.ref == .unknown(app: "mail", kind: "thread", id: "t1"))
        let entries = try decoder.decode([TranscriptEntry].self, from: Data(#"[{"kind":"thought","text":"t"}]"#.utf8))
        #expect(entries.first?.kind == .unknown)
        let item = try decoder.decode(WorkItemState.self, from: Data(#""archived""#.utf8))
        #expect(item == .unknown)
        let trigger = try decoder.decode(Trigger.self, from: Data(#"{"kind":"webhook","url":"u"}"#.utf8))
        #expect(trigger == .unknown)
        #expect(try decoder.decode(RoutineState.self, from: Data(#""retired""#.utf8)) == .unknown)
        #expect(try decoder.decode(RoutineNotify.self, from: Data(#""digest""#.utf8)) == .unknown)
    }

    @Test("Requests are snake_case")
    func requests() throws {
        let encoder = Wire.encoder()
        encoder.outputFormatting = .sortedKeys
        func json(_ value: some Encodable) throws -> String { String(bytes: try encoder.encode(value), encoding: .utf8) ?? "" }
        #expect(try json(NewWorkItem(title: "t", owner: "e", nextAction: "n", dueAt: "d", projectID: "p"))
            == #"{"due_at":"d","next_action":"n","owner":"e","project_id":"p","title":"t"}"#)
        #expect(try json(WorkItemChange(expectedRevision: 2, nextAction: "n", waitCondition: .clear, dueAt: .set("d")))
            == #"{"due_at":"d","expected_revision":2,"next_action":"n","wait_condition":null}"#)
        #expect(try json(Reaction(targetID: "m", targetText: "t", emoji: "👍", isOn: true))
            == #"{"emoji":"👍","on":true,"target_id":"m","target_text":"t"}"#)
        #expect(try json(NewMessage(id: "m", text: "t", replyTo: "r", viaVoice: true))
            == #"{"id":"m","reply_to":"r","text":"t","via_voice":true}"#)
        #expect(try json(SidebarMark(hidden: true)) == #"{"hidden":true}"#)
        #expect(try json(SidebarMark(pinned: false, unread: true)) == #"{"pinned":false,"unread":true}"#)
        #expect(try json(NewBusiness(name: "Acme", brief: "Roofs")) == #"{"brief":"Roofs","name":"Acme"}"#)
        let coding = try json(NewCodingSession(employee: "e", provider: "codex", objective: "o", repository: nil, newRepository: "site"))
        #expect(coding.contains(#""client_id":"#) && coding.contains(#""new_repository":"site""#))
    }
}
