import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@MainActor
private func settle(_ what: String, until condition: @MainActor () -> Bool) async {
    for _ in 0..<8_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(what)")
}

private actor Calls {
    var signedOut = 0
    var stops = 0
    var statusLoads = 0

    func signOut() { signedOut += 1 }
    func stop() { stops += 1 }
    func loadedStatus() { statusLoads += 1 }
}

private let server = URL(string: "http://127.0.0.1:5173")!

@MainActor
@Suite("Root routing")
struct RootRoutingTests {
    @Test("The session phase stream owns the route")
    func routesOnPhase() async {
        let (phases, continuation) = AsyncStream<SessionPhase>.makeStream()
        let store = withDependencies {
            $0.sessionClient = SessionClient(
                phases: { phases },
                signOut: {}
            )
            $0.runtimeClient = .fixture
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: DevysApp.State()) { DevysApp() }
        }
        #expect(store.route == .launching)
        continuation.yield(.signedOut)
        await settle("signed out") { store.route == .signedOut }
        #expect(store.signIn != nil && store.workspace == nil)
        continuation.yield(.signedIn(server: server))
        await settle("signed in") { store.route == .signedIn }
        #expect(store.signIn == nil && store.workspace != nil)
    }

    @Test("Signed in with no business, the workspace opens the New business form; creating one closes it")
    func firstBusiness() async {
        let created = LockIsolated(false)
        var runtime = RuntimeClient.fixture
        runtime.account = { created.value ? .fixture : Account(person: Person(id: "p", displayName: "Owner"), businesses: []) }
        runtime.createBusiness = { business in
            created.setValue(true)
            return Business(id: "acme", name: business.name, brief: business.brief)
        }
        let store = withDependencies {
            $0.runtimeClient = runtime
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: server)) { Workspace() }
        }
        await settle("form") { store.spawn(\.preferences)?.newBusiness != nil }
        guard let preferences = store.spawn(\.preferences), var draft = preferences.newBusiness else { return }
        draft.name = "Acme"
        preferences.send(.newBusinessEdited(draft))
        preferences.send(.createBusinessTapped)
        await settle("created") { preferences.businesses.isEmpty == false }
        store.send(.preferencesToggled(false))
        await settle("workspace") { store.businesses.isEmpty == false }
        #expect(store.preferences == nil)
    }
}

@MainActor
@Suite("Workspace")
struct WorkspaceFeatureTests {
    private func makeStore(
        calls: Calls,
        status: @escaping @Sendable () async throws -> EmployeeStatus = { .fixture }
    ) -> StoreOf<Workspace> {
        withDependencies {
            $0.sessionClient = SessionClient(
                phases: { AsyncStream { $0.finish() } },
                signOut: { await calls.signOut() }
            )
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { _ in
                    await calls.loadedStatus()
                    return try await status()
                },
                stop: { _ in
                    await calls.stop()
                    return true
                },
                memory: { _ in MemoryClaim.fixtures }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: server)) { Workspace() }
        }
    }

    @Test("Mounting loads the person's businesses, the first business's team, then its status and memory")
    func loadsLive() async {
        let store = makeStore(calls: Calls())
        await settle("status and memory") { store.status.value != nil && store.memory.value != nil }
        #expect(store.businesses.map(\.name) == ["Acme", "Globex"])
        #expect(store.snapshot.businessName == "Acme")
        #expect(store.snapshot.employees.first?.name == "Chief of Staff")
        #expect(store.chiefOfStaffScope == EmployeeScope(businessID: "acme", employeeID: "ops"))
        #expect(store.status.value == .fixture)
        #expect(store.memory.value == MemoryClaim.fixtures)
        #expect(store.ownerFirstName == "Mitch")
    }

    @Test("An ended session shows no error: the session hub signs the device out")
    func endedSession() async {
        let calls = Calls()
        let store = makeStore(calls: calls) { throw DevysHTTPError.unauthorized }
        for _ in 0..<2_000 where await calls.statusLoads == 0 { await Task.yield() }
        for _ in 0..<200 { await Task.yield() }
        #expect(store.status.value == nil && store.notice == nil)
        if case .failed = store.status { Issue.record("an ended session is not an error") }
    }

    @Test("The 5 s refresh pauses in the background; coming back reads everything at once")
    func pausesInBackground() async {
        let calls = Calls()
        let store = makeStore(calls: calls)
        await settle("first load") { store.status.value != nil }
        for _ in 0..<200 { await Task.yield() }
        let before = await calls.statusLoads
        store.send(.activeChanged(false))
        store.send(Workspace.Action(.tick))
        for _ in 0..<200 { await Task.yield() }
        #expect(await calls.statusLoads == before)
        store.send(.activeChanged(true))
        for _ in 0..<2_000 where await calls.statusLoads == before { await Task.yield() }
        #expect(await calls.statusLoads > before)
    }

    @Test("A failed refresh keeps the last snapshot and says it is stale")
    func keepsLastSnapshot() async {
        let calls = Calls()
        let store = makeStore(calls: calls) {
            if await calls.statusLoads > 1 { throw DevysHTTPError.unreachable("offline") }
            return .fixture
        }
        await settle("first load") { store.status.value != nil }
        store.send(.refreshTapped)
        await settle("stale notice") { store.notice != nil }
        #expect(store.status.value == .fixture)
        #expect(store.notice?.contains("last update") == true)
    }

    @Test("Stop reaches the runtime and reports that sent work is not unsent")
    func stops() async {
        let calls = Calls()
        let store = makeStore(calls: calls)
        await settle("team") { store.chiefOfStaffScope != nil }
        store.send(.stopTapped)
        await settle("stop finished") { !store.isStopping && store.notice != nil }
        #expect(await calls.stops == 1)
        #expect(store.notice?.contains("cannot be unsent") == true)
    }

    @Test("Switching business loads that business's team and returns to Home")
    func switchesBusiness() async {
        let store = makeStore(calls: Calls())
        await settle("team") { store.chiefOfStaffScope != nil }
        store.send(.placeSelected(.project("launch")))
        store.send(.layerOpened(.app("documents")))
        store.send(.businessSelected("globex"))
        #expect(store.snapshot.businessName == "Globex")
        #expect(store.place == .home && store.layers.isEmpty && store.history.isEmpty)
        await settle("Globex's team") { store.chiefOfStaffScope?.businessID == "globex" }
        // A status answer for the business just left is ignored.
        store.send(Workspace.Action(.statusLoaded(EmployeeScope(businessID: "acme", employeeID: "ops"), .fixture)))
        #expect(store.status.value == nil)
        store.send(.businessSelected("acme"))
        #expect(store.snapshot.businessName == "Acme")
    }

    @Test("Sidebar and palette toggle independently")
    func toggles() {
        let store = makeStore(calls: Calls())
        store.send(.sidebarToggled)
        store.send(.paletteToggled(true))
        #expect(!store.isSidebarVisible)
        #expect(store.isPaletteOpen)
    }
}

private actor AccessServer {
    var grants: [AccessGrant] = [
        AccessGrant(id: "g1", capability: "recall", mode: .auto, description: "Recall memory", effect: "read")
    ]
    var paused: [String: Bool] = [:]
    var pauses: [Bool] = []

    func list() -> AccessList {
        AccessList(
            grants: grants,
            available: grants.contains { $0.capability == "driveCreate" }
                ? []
                : [GrantableCapability(capability: "driveCreate", description: "Create a Drive file", effect: "external")]
        )
    }
    func grant(_ capability: String, _ mode: AccessMode) {
        grants.append(AccessGrant(id: "g\(grants.count + 1)", capability: capability, mode: mode, description: "", effect: "external"))
    }
    func revoke(_ id: String) { grants.removeAll { $0.id == id } }
    func setPaused(_ id: String, _ value: Bool) {
        paused[id] = value
        pauses.append(value)
    }
    func detail(_ businessID: String) -> BusinessDetail {
        let base = BusinessDetail.fixture(businessID)
        let employees = base.employees.map { employee -> Employee in
            var copy = employee
            copy.paused = paused[employee.id] ?? false
            return copy
        }
        return BusinessDetail(business: base.business, employees: employees, artifacts: [])
    }
}

@MainActor
@Suite("Access and pause")
struct AccessFeatureTests {
    private func makeStore(_ server: AccessServer) -> StoreOf<Workspace> {
        withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { await server.detail($0) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] },
                access: { _ in await server.list() },
                grant: { _, capability, mode in await server.grant(capability, mode) },
                revoke: { _, id in await server.revoke(id) },
                setPaused: { scope, value in await server.setPaused(scope.employeeID, value) }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: localServer)) { Workspace() }
        }
    }

    @Test("The desk's Access shows real grants; granting and revoking come back from the server")
    func grants() async {
        let server = AccessServer()
        let store = makeStore(server)
        await settle("team", until: { store.chiefOfStaffScope != nil })
        store.send(.accessRequested("ops"))
        await settle("access", until: { store.access.value != nil })
        #expect(store.access.value?.grants.map(\.capability) == ["recall"])
        #expect(store.access.value?.available.map(\.capability) == ["driveCreate"])
        store.send(.grantTapped("ops", "driveCreate", .ask))
        await settle("granted", until: { store.access.value?.grants.count == 2 })
        #expect(store.access.value?.grants.last?.mode == .ask)
        store.send(.revokeTapped("ops", "g1"))
        await settle("revoked", until: { store.access.value?.grants.map(\.capability) == ["driveCreate"] })
    }

    @Test("Pausing shows at once and reaches the server; resuming too")
    func pause() async {
        let server = AccessServer()
        let store = makeStore(server)
        await settle("team", until: { store.chiefOfStaffScope != nil })
        store.send(.pauseToggled("growth"))
        #expect(store.snapshot.employees.first { $0.id == "growth" }?.paused == true)
        for _ in 0..<2_000 where await server.pauses.isEmpty { await Task.yield() }
        #expect(await server.pauses == [true])
        store.send(.pauseToggled("growth"))
        await settle("resumed", until: { store.snapshot.employees.first { $0.id == "growth" }?.paused == false })
        for _ in 0..<2_000 where await server.pauses.count < 2 { await Task.yield() }
        #expect(await server.pauses == [true, false])
    }
}

private let localServer = URL(string: "http://127.0.0.1:5173")!

private struct StateChange: Equatable {
    let id: String
    let revision: Int
    let state: WorkItemState
}

private actor WorkServer {
    var workItems = [WorkItem(id: "c1", ownerEmployeeID: "ops", title: "Launch Acme", state: .inProgress, revision: 3)]
    var answers: [(String, Bool)] = []
    var stateChanges: [StateChange] = []
    var created: [NewWorkItem] = []
    var projects = [Project(id: "p1", name: "Launch")]
    var home = Home(needsYou: [
        NeedsYouItem(Decision(id: "d1", employeeID: "growth", capability: "driveCreate", input: .object(["name": .string("inquiry.txt")])), title: "Create inquiry.txt")
    ])
    var added: [String] = []

    func add(_ project: String, _ ref: Ref) {
        added.append("\(project):\(ref)")
        projects = projects.map { item in
            item.id == project ? Project(id: item.id, name: item.name, items: item.items + [ProjectItem(id: "i\(added.count)", ref: ref)]) : item
        }
    }

    func answer(_ id: String, _ approve: Bool) {
        answers.append((id, approve))
        home = home.answering(id)
    }
    func update(_ id: String, _ change: WorkItemChange) throws -> WorkItem {
        guard let index = workItems.firstIndex(where: { $0.id == id }) else { throw DevysHTTPError.rejected(status: 404, message: "") }
        let item = workItems[index]
        if let state = change.state { stateChanges.append(StateChange(id: id, revision: change.expectedRevision, state: state)) }
        guard item.revision == change.expectedRevision else { throw DevysHTTPError.rejected(status: 409, message: "changed") }
        let updated = WorkItem(
            id: item.id,
            ownerEmployeeID: change.owner ?? item.ownerEmployeeID,
            title: item.title,
            nextAction: change.nextAction ?? item.nextAction,
            state: change.state ?? item.state,
            revision: item.revision + 1
        )
        workItems[index] = updated
        return updated
    }
    func create(_ newItem: NewWorkItem) -> WorkItem {
        created.append(newItem)
        let item = WorkItem(id: "c\(workItems.count + 1)", ownerEmployeeID: newItem.owner, title: newItem.title, projectID: newItem.projectID)
        workItems.append(item)
        return item
    }
}

@MainActor
@Suite("Work and decisions")
struct WorkFeatureTests {
    private func makeStore(_ server: WorkServer) -> StoreOf<Workspace> {
        withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] },
                work: { _ in await server.workItems },
                createWorkItem: { _, newItem in await server.create(newItem) },
                updateWorkItem: { _, id, change in try await server.update(id, change) },
                answer: { _, id, approve in await server.answer(id, approve) },
                projects: { _ in await server.projects },
                addToProject: { _, project, ref in await server.add(project, ref) },
                home: { _ in await server.home }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: localServer)) { Workspace() }
        }
    }

    @Test("Real work, requests, projects and Home load with the team; Home's panel shows what needs the owner")
    func loads() async {
        let store = makeStore(WorkServer())
        await settle("work", until: { store.work.value != nil && store.home.value != nil })
        #expect(store.work.value?.filter { $0.state.group == .inProgress }.map(\.title) == ["Launch Acme"])
        #expect(store.projects.value?.map(\.name) == ["Launch"])
        #expect(store.home.value?.needsYou.map(\.id) == ["d1"] && store.state.decisions.first?.capability == "driveCreate")
        #expect(store.state.hasPermanent && store.state.isPanelOpen)
    }

    @Test("Answering a request removes it at once and tells the server exactly once")
    func answers() async {
        let server = WorkServer()
        let store = makeStore(server)
        await settle("work", until: { store.state.decisions.count == 1 })
        store.send(.decisionAnswered("d1", approve: true))
        #expect(store.state.decisions.isEmpty && store.home.value?.needsYou.isEmpty == true)
        for _ in 0..<2_000 where await server.answers.isEmpty { await Task.yield() }
        let answers = await server.answers
        #expect(answers.count == 1 && answers.first?.0 == "d1" && answers.first?.1 == true)
    }

    @Test("Keeping a page on a project comes back from the server as a reference")
    func keeps() async {
        let server = WorkServer()
        let store = makeStore(server)
        await settle("projects", until: { store.projects.value?.first?.name == "Launch" })
        store.send(.projectItemAdded("p1", .artifact("a1")))
        await settle("kept", until: { store.projects.value?.first?.items.contains { $0.ref == .artifact("a1") } == true })
        #expect(await server.added == ["p1:devys:documents/artifact/a1"])
    }

    @Test("A new work item defaults to the Chief of Staff and opens its thread; state changes carry the revision on screen")
    func changes() async {
        let server = WorkServer()
        let store = makeStore(server)
        await settle("work", until: { store.work.value != nil && store.chiefOfStaffScope != nil })
        store.send(.newWorkItemTapped())
        guard var draft = store.newWorkItem else { return #expect(Bool(false), "the sheet opens") }
        #expect(draft.ownerID == "ops" && draft.projectID == nil)
        draft.title = "  Draft the PR inquiry  "
        store.send(.workItemEdited(draft))
        store.send(.workItemConfirmed)
        await settle("created", until: { store.work.value?.count == 2 && store.newWorkItem == nil && store.place == .thread("c2") })
        let created = await server.created
        #expect(created.first?.title == "Draft the PR inquiry" && created.first?.owner == "ops")
        store.send(.workItemStateSet("c1", .waiting))
        for _ in 0..<2_000 where await server.stateChanges.isEmpty { await Task.yield() }
        let change = await server.stateChanges.first
        #expect(change == StateChange(id: "c1", revision: 3, state: .waiting))
    }
}

private actor ModelServer {
    var saved: [String: String] = [:]
    var requests: [String] = []
    var refuses = false

    func refuse() { refuses = true }
    func set(_ employeeID: String, _ model: String) throws -> String {
        requests.append("\(employeeID):\(model)")
        if refuses { throw DevysHTTPError.rejected(status: 403, message: "Forbidden") }
        saved[employeeID] = model
        return model
    }
}

@MainActor
@Suite("Employee models")
struct ModelFeatureTests {
    private func makeStore(_ server: ModelServer) -> StoreOf<Workspace> {
        withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] },
                models: { .golden },
                setModel: { scope, model in try await server.set(scope.employeeID, model) }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: localServer)) { Workspace() }
        }
    }

    private func model(_ store: StoreOf<Workspace>, _ id: String) -> String? {
        store.snapshot.employees.first { $0.id == id }?.model
    }

    @Test("Opening an employee's desk loads the catalog and that employee's spend")
    func loadsCatalogAndUsage() async {
        let store = makeStore(ModelServer())
        await settle("team", until: { store.chiefOfStaffScope != nil })
        store.send(.modelRequested("growth"))
        await settle("catalog", until: { store.models.catalog != nil && store.models.usage["growth"] != nil })
        #expect(store.models.catalog == .golden)
        #expect(store.models.usage["growth"]?.totalCost == 0.0625)
        await settle("operations' spend from its status", until: { store.state.usage(of: "ops") != nil })
    }

    @Test("Choosing a model shows at once and keeps what the server saved")
    func changes() async {
        let server = ModelServer()
        let store = makeStore(server)
        await settle("team", until: { store.chiefOfStaffScope != nil })
        #expect(model(store, "growth") == "claude-opus-5-5")
        store.send(.modelSelected("growth", "gpt-6.1-sol"))
        #expect(model(store, "growth") == "gpt-6.1-sol")
        for _ in 0..<2_000 where await server.requests.isEmpty { await Task.yield() }
        #expect(await server.requests == ["growth:gpt-6.1-sol"])
        #expect(model(store, "growth") == "gpt-6.1-sol")
        #expect(store.models.errors["growth"] == nil)
        // Choosing the current model again sends nothing.
        store.send(.modelSelected("growth", "gpt-6.1-sol"))
        for _ in 0..<200 { await Task.yield() }
        #expect(await server.requests.count == 1)
    }

    @Test("A refused change puts the previous model back and says why")
    func rollsBack() async {
        let server = ModelServer()
        await server.refuse()
        let store = makeStore(server)
        await settle("team", until: { store.chiefOfStaffScope != nil })
        store.send(.modelSelected("growth", "gemini-3.8-flash"))
        #expect(model(store, "growth") == "gemini-3.8-flash")
        await settle("rollback", until: { store.models.errors["growth"] != nil })
        #expect(model(store, "growth") == "claude-opus-5-5")
        #expect(store.models.errors["growth"] == "You can't change this employee's model.")
    }
}
