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
        "apps": { try await $0.apps($1, businessID: "b1") },
        "browser": { try await $0.browserStatus($1, businessID: "b1") },
        "business-created": { try await $0.createBusiness($1, NewBusiness(name: "Acme Roofing")) },
        "business-updated": { try await $0.updateBusiness($1, id: "b1", name: nil, brief: "Roof repairs.") },
        "business": { try await $0.business($1, id: "b1") },
        "coded-work": { try await $0.codingWork($1, businessID: "b1") },
        "coding-sessions": { try await $0.codingSessions($1, businessID: "b1", workID: "w1") },
        "conversation-work": { try await $0.conversation($1, businessID: "b1", key: .work("w1")) },
        "conversation": { try await $0.conversation($1, businessID: "b1", key: .direct("e1")) },
        "conversations": { try await $0.conversations($1, businessID: "b1") },
        "decisions": { try await $0.decisions($1, businessID: "b1", workItemID: "w1") },
        "device-code": { try await $0.issueDeviceCode($1) },
        "devices": { try await $0.devices($1) },
        "diff": { try await $0.sessionDiff($1, businessID: "b1", workID: "w1", sessionID: "s1") },
        "employee": { try await $0.hire($1, businessID: "b1", Hire(template: "engineering", name: "Ada")) },
        "file-text": { try await $0.fileText($1, businessID: "b1", path: "/brief.md") },
        "files": { try await $0.files($1, businessID: "b1", path: nil).entries },
        "google": { try await $0.googleConnection($1, businessID: "b1") },
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
        "screenshot": { try await $0.browserPicture($1, businessID: "b1") },
        "status": { try await $0.status($1, scope) },
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

    @Test("Golden values land in the right fields")
    func values() async throws {
        let home = try await Self.answering("home").home(Self.session, businessID: "b1")
        #expect(home.needsYou.first?.kind == .decision && home.needsYou.first?.workID != nil && home.needsYou.first?.projectID != nil)
        #expect(home.decisions.first?.capability == "driveCreate" && home.decisions.first?.input.fields.first?.key == "content")
        #expect(home.glance.moving.first?.state == .inProgress && home.glance.moving.first?.dueAt != nil)

        let work = try await Self.answering("work").work(Self.session, businessID: "b1")
        let evidence = try #require(work.last?.evidence.first)
        #expect(evidence.check?.exitCode == 0 && evidence.deploy?.live == true && evidence.recordedAt.hasSuffix("Z"))
        #expect(work.first?.waitCondition == "The supplier confirms the price" && work.first?.projectID != nil)

        let detail = try await Self.answering("business").business(Self.session, id: "b1")
        #expect(detail.employees.last?.responsibilities.hasPrefix("Build, fix") == true && detail.employees.last?.look != nil)
        #expect(detail.members.first?.displayName == "Owner" && detail.artifacts.first?.byteLength == 1840)
        #expect(detail.artifacts.first?.latestID == "00000000-0000-4000-8000-000000000006")

        let status = try await Self.answering("status").status(Self.session, Self.scope)
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

        let code = try await Self.answering("device-code").issueDeviceCode(Self.session)
        #expect(code.expiresAt == ServerDate.parse("2026-01-01T00:00:00.000Z"))

        let thread = try await Self.answering("conversation-work").conversation(Self.session, businessID: "b1", key: .work("w1"))
        #expect(thread.messages.first?.ref == .workItem("00000000-0000-4000-8000-000000000008") && thread.messages.first?.isEvent == true)

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
            from: Data(#"{"id":"mail","name":"Mail","icon":"","summary":"","kind":"remote","status":"beta","records":[],"skills":[],"installed":true,"pinned":true,"visible":true}"#.utf8)
        )
        #expect(app.kind == .unknown && app.status == .unknown)
        let message = try decoder.decode(
            ConversationMessage.self,
            from: Data(#"{"id":"m","author":"system","kind":"event","text":"t","ref":"devys:mail/thread/t1","created_at":"2026-01-01T00:00:00.000Z"}"#.utf8)
        )
        #expect(message.ref == .unknown(app: "mail", kind: "thread", id: "t1"))
        let entries = try decoder.decode([TranscriptEntry].self, from: Data(#"[{"kind":"thought","text":"t"}]"#.utf8))
        #expect(entries.first?.kind == .unknown)
        let item = try decoder.decode(WorkItemState.self, from: Data(#""archived""#.utf8))
        #expect(item == .unknown)
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
        let coding = try json(NewCodingSession(employee: "e", provider: "codex", objective: "o", repository: nil, newRepository: "site"))
        #expect(coding.contains(#""client_id":"#) && coding.contains(#""new_repository":"site""#))
    }
}
