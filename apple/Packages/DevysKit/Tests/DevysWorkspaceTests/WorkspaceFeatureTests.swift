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
    var signIns: [(URL, String)] = []
    var expired = 0
    var signedOut = 0
    var stops = 0
    var statusLoads = 0

    func signIn(_ server: URL, _ code: String) { signIns.append((server, code)) }
    func expire() { expired += 1 }
    func signOut() { signedOut += 1 }
    func stop() { stops += 1 }
    func loadedStatus() { statusLoads += 1 }
}

private let code = String(repeating: "ab", count: 32)
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
                signIn: { _, _ in },
                signOut: {},
                expire: {}
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
}

@MainActor
@Suite("Sign in")
struct SignInFeatureTests {
    private func makeStore(calls: Calls, fails: Bool = false) -> StoreOf<SignIn> {
        withDependencies {
            $0.sessionClient = SessionClient(
                phases: { AsyncStream { $0.finish() } },
                signIn: { server, code in
                    await calls.signIn(server, code)
                    if fails { throw DevysHTTPError.rejected(status: 401, message: "used") }
                },
                signOut: {},
                expire: {}
            )
        } operation: {
            Store(initialState: SignIn.State()) { SignIn() }
        }
    }

    @Test("Only a valid server and a 64-hex code can submit")
    func validation() {
        let store = makeStore(calls: Calls())
        #expect(!store.canSubmit)
        store.send(.codeChanged("not-a-code"))
        #expect(!store.canSubmit)
        store.send(.codeChanged("  \(code.uppercased())\n"))
        #expect(store.canSubmit)
        store.send(.serverChanged("ftp://example.com"))
        #expect(!store.canSubmit)
    }

    @Test("Submitting sends the normalized code to the chosen server")
    func submits() async {
        let calls = Calls()
        let store = makeStore(calls: calls)
        store.send(.codeChanged(" \(code.uppercased()) "))
        store.send(.submitTapped)
        #expect(store.isSubmitting)
        for _ in 0..<1_000 where await calls.signIns.isEmpty { await Task.yield() }
        let sent = await calls.signIns
        #expect(sent.count == 1)
        #expect(sent.first?.0 == server)
        #expect(sent.first?.1 == code)
    }

    @Test("A used code shows how to get a new one")
    func failureCopy() async {
        let store = makeStore(calls: Calls(), fails: true)
        store.send(.codeChanged(code))
        store.send(.submitTapped)
        await settle("failure") { store.errorText != nil }
        #expect(!store.isSubmitting)
        #expect(store.errorText?.contains("scripts/enroll.ts") == true)
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
                signIn: { _, _ in },
                signOut: { await calls.signOut() },
                expire: { await calls.expire() }
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
        #expect(store.snapshot.employees.first?.name == "Head of Operations")
        #expect(store.operationsScope == EmployeeScope(businessID: "acme", employeeID: "ops"))
        #expect(store.status.value == .fixture)
        #expect(store.memory.value == MemoryClaim.fixtures)
        #expect(store.ownerFirstName == "Mitch")
    }

    @Test("An ended session expires locally instead of showing an error")
    func expiresOnUnauthorized() async {
        let calls = Calls()
        let store = makeStore(calls: calls) { throw DevysHTTPError.unauthorized }
        for _ in 0..<2_000 where await calls.expired == 0 { await Task.yield() }
        #expect(await calls.expired == 1)
        #expect(store.status.value == nil)
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
        await settle("team") { store.operationsScope != nil }
        store.send(.stopTapped)
        await settle("stop finished") { !store.isStopping && store.notice != nil }
        #expect(await calls.stops == 1)
        #expect(store.notice?.contains("cannot be unsent") == true)
    }

    @Test("Switching business loads that business's team and returns to Today")
    func switchesBusiness() async {
        let store = makeStore(calls: Calls())
        await settle("team") { store.operationsScope != nil }
        store.send(.pageSelected(.approvals))
        store.send(.businessSelected("globex"))
        #expect(store.snapshot.businessName == "Globex")
        #expect(store.page == .today)
        await settle("Globex's team") { store.operationsScope?.businessID == "globex" }
        // A status answer for the business just left is ignored.
        store.send(Workspace.Action(.statusLoaded(EmployeeScope(businessID: "acme", employeeID: "ops"), .fixture)))
        #expect(store.status.value == nil)
        store.send(.businessSelected("acme"))
        #expect(store.snapshot.businessName == "Acme")
    }

    @Test("Each rail destination opens its default page")
    func destinationsOpenDefaults() {
        let store = makeStore(calls: Calls())
        store.send(.destinationSelected(.team))
        #expect(store.page == .employee(WorkspaceSnapshot.acmeLaunch.employees.first?.id))
        store.send(.destinationSelected(.inbox))
        #expect(store.page == .inbox)
        store.send(.destinationSelected(.work))
        #expect(store.page == .work(.all))
        #expect(store.destination == .work)
    }

    @Test("Opening a different space starts on its conversation")
    func spaceTabsReset() {
        let store = makeStore(calls: Calls())
        store.send(.pageSelected(.space("space-launch")))
        store.send(.spaceTabSelected(.files))
        store.send(.pageSelected(.space("space-growth")))
        #expect(store.spaceTab == .conversation)
        #expect(store.main?.key == .space("space-growth"))
    }

    @Test("Sidebar, inspector and palette toggle independently")
    func panels() {
        let store = makeStore(calls: Calls())
        store.send(.inspectorToggled)
        store.send(.paletteToggled(true))
        #expect(!store.isInspectorVisible)
        #expect(store.isSidebarVisible)
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

    @Test("The Access tab shows real grants; granting and revoking come back from the server")
    func grants() async {
        let server = AccessServer()
        let store = makeStore(server)
        await settle("team", until: { store.operationsScope != nil })
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

    @Test("Pausing shows at once, reaches the server, and presence shows the employee paused")
    func pause() async {
        let server = AccessServer()
        let store = makeStore(server)
        await settle("team", until: { store.operationsScope != nil })
        store.send(.pauseToggled("growth"))
        #expect(store.snapshot.employees.first { $0.id == "growth" }?.paused == true)
        await settle("server", until: { store.state.presence.first { $0.id == "growth" }?.signal == .paused })
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
    let state: CommitmentState
}

private actor WorkServer {
    var commitments = [Commitment(id: "c1", ownerEmployeeID: "ops", title: "Launch Acme", state: .inProgress, revision: 3)]
    var decisions = [Decision(id: "d1", employeeID: "growth", capability: "driveCreate", input: .object(["name": .string("inquiry.txt")]))]
    var answers: [(String, Bool)] = []
    var stateChanges: [StateChange] = []
    var created: [NewTask] = []
    var spaces = [Space(id: "s1", name: "Launch", items: [SpaceItem(id: "i1", kind: .commitment, ref: "c1")])]
    var added: [String] = []

    func add(_ space: String, _ ref: String) {
        added.append("\(space):\(ref)")
        spaces = spaces.map { item in
            item.id == space ? Space(id: item.id, name: item.name, items: item.items + [SpaceItem(id: "i\(added.count + 1)", kind: .commitment, ref: ref)]) : item
        }
    }

    func answer(_ id: String, _ approve: Bool) {
        answers.append((id, approve))
        decisions.removeAll { $0.id == id }
    }
    func update(_ id: String, _ change: CommitmentChange) throws -> Commitment {
        guard let index = commitments.firstIndex(where: { $0.id == id }) else { throw DevysHTTPError.rejected(status: 404, message: "") }
        let item = commitments[index]
        if let state = change.state { stateChanges.append(StateChange(id: id, revision: change.expectedRevision, state: state)) }
        guard item.revision == change.expectedRevision else { throw DevysHTTPError.rejected(status: 409, message: "changed") }
        let updated = Commitment(
            id: item.id,
            ownerEmployeeID: change.owner ?? item.ownerEmployeeID,
            title: item.title,
            nextAction: change.nextAction ?? item.nextAction,
            state: change.state ?? item.state,
            revision: item.revision + 1
        )
        commitments[index] = updated
        return updated
    }
    func create(_ task: NewTask) -> Commitment {
        created.append(task)
        let item = Commitment(id: "c\(commitments.count + 1)", ownerEmployeeID: task.owner, title: task.title)
        commitments.append(item)
        if let space = task.spaceId { add(space, item.id) }
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
                work: { _ in await server.commitments },
                createCommitment: { _, task in await server.create(task) },
                updateCommitment: { _, id, change in try await server.update(id, change) },
                decisions: { _ in await server.decisions },
                answer: { _, id, approve in await server.answer(id, approve) },
                spaces: { _ in await server.spaces },
                addToSpace: { _, space, _, ref in await server.add(space, ref) }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: localServer)) { Workspace() }
        }
    }

    @Test("Real work and requests load with the team; needs-you counts the requests")
    func loads() async {
        let store = makeStore(WorkServer())
        await settle("work", until: { store.work.value != nil && store.decisions.value != nil })
        #expect(store.state.work(.inProgress).map(\.title) == ["Launch Acme"])
        #expect(store.state.needsYouCount == 1)
        #expect(store.state.presence.first { $0.id == "growth" }?.signal == .needsYou(1))
    }

    @Test("Answering a request removes it at once and tells the server exactly once")
    func answers() async {
        let server = WorkServer()
        let store = makeStore(server)
        await settle("work", until: { store.decisions.value?.count == 1 })
        store.send(.decisionAnswered("d1", approve: true))
        #expect(store.decisions.value?.isEmpty == true)
        for _ in 0..<2_000 where await server.answers.isEmpty { await Task.yield() }
        let answers = await server.answers
        #expect(answers.count == 1 && answers.first?.0 == "d1" && answers.first?.1 == true)
    }

    @Test("Spaces load with work and show references; adding one comes back from the server")
    func spaces() async {
        let server = WorkServer()
        let store = makeStore(server)
        await settle("spaces", until: { store.spaces.value?.first?.name == "Launch" })
        #expect(store.spaces.value?.first?.refs(.commitment) == ["c1"])
        store.send(.spaceItemAdded("s1", .commitment, "c9"))
        await settle("added", until: { store.spaces.value?.first?.refs(.commitment) == ["c1", "c9"] })
        #expect(await server.added == ["s1:c9"])
    }

    @Test("A new task from Work defaults to the Head of Operations; state changes carry the revision on screen")
    func changes() async {
        let server = WorkServer()
        let store = makeStore(server)
        await settle("work", until: { store.work.value != nil && store.operationsScope != nil })
        store.send(.newTaskTapped())
        guard var draft = store.newTask else { return #expect(Bool(false), "the sheet opens") }
        #expect(draft.ownerID == "ops" && draft.spaceID == nil)
        draft.title = "  Draft the PR inquiry  "
        store.send(.taskEdited(draft))
        store.send(.taskConfirmed)
        await settle("created", until: { store.work.value?.count == 2 && store.newTask == nil })
        let created = await server.created
        #expect(created.first?.title == "Draft the PR inquiry" && created.first?.owner == "ops")
        store.send(.commitmentStateSet("c1", .waiting))
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
                models: { .fixture },
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

    @Test("Opening an employee loads the catalog and that employee's spend")
    func loadsCatalogAndUsage() async {
        let store = makeStore(ModelServer())
        await settle("team", until: { store.operationsScope != nil })
        store.send(.modelRequested("growth"))
        await settle("catalog", until: { store.models.catalog != nil && store.models.usage["growth"] != nil })
        #expect(store.models.catalog == .fixture)
        #expect(store.models.usage["growth"]?.totalCost == 0.0625)
        await settle("operations' spend from its status", until: { store.state.usage(of: "ops") != nil })
    }

    @Test("Choosing a model shows at once and keeps what the server saved")
    func changes() async {
        let server = ModelServer()
        let store = makeStore(server)
        await settle("team", until: { store.operationsScope != nil })
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
        await settle("team", until: { store.operationsScope != nil })
        store.send(.modelSelected("growth", "gemini-3.8-flash"))
        #expect(model(store, "growth") == "gemini-3.8-flash")
        await settle("rollback", until: { store.models.errors["growth"] != nil })
        #expect(model(store, "growth") == "claude-opus-5-5")
        #expect(store.models.errors["growth"] == "You can't change this employee's model.")
    }
}
