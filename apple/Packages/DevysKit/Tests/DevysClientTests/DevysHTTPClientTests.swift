import DevysClient
import Foundation
import Testing

@Suite("Devys HTTP API")
struct DevysHTTPClientTests {
    private actor Recorder {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
    }

    private static let server = URL(string: "https://devys.test")!
    private static let scope = EmployeeScope(businessID: "b1", employeeID: "e1")

    private func api(
        status: Int = 200,
        body: String,
        recorder: Recorder = Recorder()
    ) -> DevysHTTPClient {
        DevysHTTPClient { request in
            await recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    @Test("Enrollment posts the one-time code and returns a device session")
    func enroll() async throws {
        let recorder = Recorder()
        let session = try await api(body: #"{"sessionToken":"abc","expiresInSeconds":604800}"#, recorder: recorder)
            .enroll(server: Self.server, code: "f00d")
        #expect(session == DeviceSession(server: Self.server, token: "abc"))
        let request = try #require(await recorder.requests.first)
        #expect(request.url?.absoluteString == "https://devys.test/api/native/session")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["token": "f00d"])
    }

    @Test("Account lists the person's businesses; a business lists its team")
    func directory() async throws {
        let session = DeviceSession(server: Self.server, token: "tok")
        let recorder = Recorder()
        let account = try await api(
            body: #"{"person":{"id":"p1","display_name":"Mitch"},"businesses":[{"id":"b1","name":"Acme"}]}"#,
            recorder: recorder
        ).account(session)
        #expect(account.person.displayName == "Mitch")
        #expect(account.businesses == [Business(id: "b1", name: "Acme")])
        let detail = try await api(
            body: """
            {"business":{"id":"b1","name":"Acme"},
             "employees":[{"id":"e1","business_id":"b1","name":"Head of Operations","role":"Runs the business.","model":"gpt-6.1-sol"}],
             "artifacts":[{"id":"a1","filename":"x.md","content_type":"text/markdown","byte_length":3,"created_at":"2026-10-19"}]}
            """,
            recorder: recorder
        ).business(session, id: "b1")
        #expect(detail.employees.map(\.name) == ["Head of Operations"])
        #expect(detail.employees.first?.summary == "Runs the business.")
        #expect(detail.employees.first?.model == "gpt-6.1-sol")
        #expect(detail.artifacts.first?.byteLength == 3)
        let paths = await recorder.requests.map { $0.url?.path() }
        #expect(paths == ["/api/me", "/api/businesses/b1"])
    }

    @Test("Employee status uses the bearer session and the employee's path")
    func status() async throws {
        let recorder = Recorder()
        let body = """
        {"state":{"run":{"id":"m1","stopped":false,"deadline":1760000000000},
                  "inbox":[{"id":"m1","text":"hi","receivedAt":1760000000000,"status":"running"}],
                  "outbox":[{"id":"m0","chatId":"c","text":"hello","attempts":1,"status":"sent"}],
                  "checkpoint":null,"usage":{"input":1}}}
        """
        let snapshot = try await api(body: body, recorder: recorder)
            .status(DeviceSession(server: Self.server, token: "tok"), Self.scope)
        #expect(snapshot.state.run?.stopped == false)
        #expect(snapshot.state.inbox.first?.status == "running")
        // A usage shape without per-model entries is tolerated, not an error.
        #expect(snapshot.state.usage?.totalCost == 0)
        let request = try #require(await recorder.requests.first)
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer tok")
        #expect(request.url?.path() == "/api/businesses/b1/employees/e1/status")
    }

    @Test("The model catalog decodes and groups by vendor in server order")
    func models() async throws {
        let recorder = Recorder()
        let body = """
        {"defaults":{"employee":"claude-opus-5-5","background":"gemini-3.8-flash"},"models":[
          {"id":"claude-opus-5-5","label":"Claude Opus 5.5","vendor":"Anthropic","provider":"TrueFoundry gateway",
           "summary":"Best judgment.","effort":"medium","price":{"input":5,"output":25,"cacheRead":0.5},"typicalTurnUsd":0.0625},
          {"id":"gpt-6.1-sol","label":"GPT-6.1 Sol","vendor":"OpenAI","provider":"TrueFoundry gateway",
           "summary":"All-round.","effort":"medium","price":{"input":2.5,"output":15,"cacheRead":0.25},"typicalTurnUsd":0.035},
          {"id":"claude-fable-5-1","label":"Claude Fable 5.1","vendor":"Anthropic","provider":"TrueFoundry gateway",
           "summary":"Hardest problems.","effort":"high","price":{"input":15,"output":75,"cacheRead":1.5},"typicalTurnUsd":0.2}]}
        """
        let catalog = try await api(body: body, recorder: recorder).models(DeviceSession(server: Self.server, token: "tok"))
        #expect(catalog.defaults.employee == "claude-opus-5-5")
        #expect(catalog.model("gpt-6.1-sol")?.price.cacheRead == 0.25)
        #expect(catalog.vendors.map(\.vendor) == ["Anthropic", "OpenAI"])
        #expect(catalog.vendors.first?.models.map(\.id) == ["claude-opus-5-5", "claude-fable-5-1"])
        #expect(await recorder.requests.first?.url?.path() == "/api/models")
    }

    @Test("Changing a model PUTs it to the employee and returns the saved model")
    func setModel() async throws {
        let recorder = Recorder()
        let saved = try await api(body: #"{"model":"gpt-6-luna"}"#, recorder: recorder)
            .setModel(DeviceSession(server: Self.server, token: "tok"), Self.scope, model: "gpt-6-luna")
        #expect(saved == "gpt-6-luna")
        let request = try #require(await recorder.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "/api/businesses/b1/employees/e1/model")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["model": "gpt-6-luna"])
        await #expect(throws: DevysHTTPError.rejected(status: 400, message: "Unknown model")) {
            try await api(status: 400, body: "Unknown model")
                .setModel(DeviceSession(server: Self.server, token: "tok"), Self.scope, model: "nope")
        }
    }

    @Test("Status usage sums cost across models and reports the cached share of input")
    func usage() async throws {
        let body = """
        {"state":{"run":null,"inbox":[],"outbox":[],"usage":{"models":{
          "gateway/claude-opus-5-5":{"input":2000,"output":500,"cacheRead":6000,"cacheWrite":2000,"totalTokens":10500,
            "cost":{"input":0.01,"output":0.0125,"cacheRead":0.003,"cacheWrite":0.0125,"total":0.038}},
          "gateway/gpt-6-luna":{"input":0,"output":100,"cacheRead":0,"cacheWrite":0,"totalTokens":100,
            "cost":{"input":0,"output":0.002,"cacheRead":0,"cacheWrite":0,"total":0.002}}},
          "tools":{"read":{"calls":2}}}}}
        """
        let snapshot = try await api(body: body).status(DeviceSession(server: Self.server, token: "tok"), Self.scope)
        let usage = try #require(snapshot.state.usage)
        #expect(abs(usage.totalCost - 0.04) < 0.000_001)
        #expect(usage.cacheShare == 0.6)
        let bare = try await api(body: #"{"state":{"run":null,"inbox":[],"outbox":[]}}"#)
            .status(DeviceSession(server: Self.server, token: "tok"), Self.scope)
        #expect(bare.state.usage == nil)
    }

    @Test("A 401 is an ended session; other failures stay distinguishable")
    func failures() async {
        let session = DeviceSession(server: Self.server, token: "tok")
        await #expect(throws: DevysHTTPError.unauthorized) {
            try await api(status: 401, body: "Sign in required").account(session)
        }
        await #expect(throws: DevysHTTPError.rejected(status: 503, message: "busy")) {
            try await api(status: 503, body: "busy").account(session)
        }
        await #expect(throws: DevysHTTPError.invalidResponse) {
            try await api(body: "not json").account(session)
        }
        let offline = DevysHTTPClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect {
            try await offline.account(session)
        } throws: { error in
            if case .unreachable = error as? DevysHTTPError { true } else { false }
        }
    }
}

@Suite("Session hub")
struct SessionHubTests {
    private static let server = URL(string: "https://devys.test")!

    @Test("Signing in stores the session and publishes the phase; expiry clears both")
    func lifecycle() async throws {
        let store = DeviceSessionStore.inMemory()
        let api = DevysHTTPClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"sessionToken":"issued"}"#.utf8), response)
        }
        let hub = SessionHub(api: api, store: store)
        var phases = SessionClient.live(hub).phases().makeAsyncIterator()
        #expect(await phases.next() == .signedOut)
        try await hub.signIn(server: Self.server, code: "code")
        #expect(await phases.next() == .signedIn(server: Self.server))
        #expect(store.load() == DeviceSession(server: Self.server, token: "issued"))
        await hub.expire()
        #expect(await phases.next() == .signedOut)
        #expect(store.load() == nil)
        await #expect(throws: DevysHTTPError.unauthorized) { try await hub.current() }
    }

    @Test("A stored session restores signed in")
    func restore() async {
        let hub = SessionHub(
            api: DevysHTTPClient { _ in throw URLError(.badURL) },
            store: .inMemory(DeviceSession(server: Self.server, token: "kept"))
        )
        var phases = SessionClient.live(hub).phases().makeAsyncIterator()
        #expect(await phases.next() == .signedIn(server: Self.server))
    }
}
