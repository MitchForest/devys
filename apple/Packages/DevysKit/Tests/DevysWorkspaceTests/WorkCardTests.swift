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

private let localServer = URL(string: "http://127.0.0.1:5173")!

nonisolated private func running(_ conversation: String?) -> EmployeeStatus {
    EmployeeStatus(state: RuntimeState(run: .init(id: "r1", stopped: false, deadline: nil, conversation: conversation), inbox: [], outbox: []))
}

nonisolated private let stopped = EmployeeStatus(state: RuntimeState(run: .init(id: "r0", stopped: true, deadline: nil, conversation: "work:c1"), inbox: [], outbox: []))

/// Requests from Admin on a work item, from the Chief of Staff and Admin without one, and one
/// asked in the Launch channel.
private let connect = Decision(
    id: "d-connect", kind: .connect, employeeID: "growth", capability: "askOwner",
    input: .object(["kind": .string("connect"), "app": .string("ramp"), "why": .string("To pay for the domain")]),
    workItemID: "c1", requestedAt: "2026-10-23T10:00:00.000Z"
)
private let deploy = Decision(
    id: "d-deploy", employeeID: "growth", capability: "deployProduction", input: .object([:]),
    workItemID: "c1", requestedAt: "2026-10-23T11:00:00.000Z"
)
private let hire = Decision(id: "d-hire", employeeID: "ops", capability: "hireEmployee", input: .object(["name": .string("Ada")]))
private let routine = Decision(id: "d-routine", employeeID: "growth", capability: "routineActivate", input: .object([:]))
private let channel = Decision(id: "d-channel", employeeID: "growth", capability: "driveCreate", input: .object([:]))

private actor CardServer {
    var work = [
        WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Buy the domain", state: .inProgress, revision: 2),
        WorkItem(id: "c2", ownerEmployeeID: "engineering", title: "Ship the site", state: .proposed, revision: 1)
    ]
    var home = Home()
    var started: [String] = []
    var stops: [EmployeeScope] = []
    /// Each employee's run: the conversation it is running for.
    var runs: [String: String] = ["growth": "work:c1"]

    func setHome(_ home: Home) { self.home = home }

    func start(_ id: String) throws -> WorkItem {
        started.append(id)
        guard let index = work.firstIndex(where: { $0.id == id }), work[index].state == .proposed else {
            throw DevysHTTPError.rejected(status: 409, message: "That plan already started or was cancelled")
        }
        let item = work[index]
        work[index] = WorkItem(id: item.id, ownerEmployeeID: item.ownerEmployeeID, title: item.title, state: .ready, revision: item.revision + 1)
        return work[index]
    }

    func status(_ scope: EmployeeScope) -> EmployeeStatus {
        runs[scope.employeeID].map { running($0) } ?? .fixture
    }

    func stop(_ scope: EmployeeScope) -> Bool {
        stops.append(scope)
        runs[scope.employeeID] = nil
        return true
    }
}

@MainActor
@Suite("Work card")
struct WorkCardTests {
    private func makeStore(_ server: CardServer) async -> StoreOf<Workspace> {
        let store: StoreOf<Workspace> = withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { await server.status($0) },
                stop: { await server.stop($0) },
                memory: { _ in [] },
                work: { _ in await server.work },
                startWork: { _, id in try await server.start(id) },
                projects: { _ in [Project(id: "p1", name: "Launch", leadEmployeeID: "growth")] },
                home: { _ in await server.home }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: localServer)) { Workspace() }
        }
        await settle("team and work", until: { store.chiefOfStaffScope != nil && store.work.value != nil && store.home.value != nil })
        return store
    }

    @Test("Home's permanent view is the Chief of Staff's desk, closed by default; a thread has none")
    func noPermanentForHomeOrThreads() async {
        let server = CardServer()
        await server.setHome(Home(needsYou: [NeedsYouItem(connect, title: "Ramp")]))
        let store = await makeStore(server)
        await settle("Home has a request", until: { store.home.value?.isEmpty == false })
        #expect(store.place == .home && store.state.hasPermanent && !store.state.isPanelOpen)
        store.send(.panelToggled)
        #expect(store.state.isPanelOpen, "Home's panel is the Chief of Staff's desk")
        store.send(.panelToggled)
        store.send(.threadOpened("c1"))
        #expect(!store.state.hasPermanent && !store.state.isPanelOpen)
        store.send(.layerOpened(.browser(workID: "c1")))
        #expect(store.state.isPanelOpen, "a layer still opens the panel")
        store.send(.placeSelected(.project("p1")))
        #expect(store.state.hasPermanent && store.state.isPanelOpen)
        store.send(.placeSelected(.direct("growth")))
        #expect(store.state.hasPermanent)
    }

    @Test("The card's one line: done, yours, your turn, ready, working, waiting, up next")
    func stateLine() {
        var state = Workspace.State(server: localServer)
        state.account = .fixture
        let steps = [WorkStep(title: "Connect Ramp", state: .done, doer: .owner), WorkStep(title: "Register it", state: .doing), WorkStep(title: "Set up email", state: .todo)]
        let working = WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Buy the domain", nextAction: "Register it", state: .inProgress, steps: steps)
        #expect(state.cardLine(working) == .upNext("Register it"), "not running: what is next")
        #expect(state.stepPosition(working) == "Step 2 of 3" && steps.map(\.text) == ["You: Connect Ramp", "Register it", "Set up email"])

        state.statuses["growth"] = running("direct:growth")
        #expect(state.cardLine(working) == .upNext("Register it"), "running for another conversation is not working on this")
        state.statuses["growth"] = stopped
        #expect(state.cardLine(working) == .upNext("Register it"))
        state.statuses["growth"] = running("work:c1")
        #expect(state.cardLine(working) == .working("Register it"))

        state.home = .loaded(Home(needsYou: [NeedsYouItem(deploy, title: "Deploy"), NeedsYouItem(connect, title: "Ramp", app: AppBadge(id: "ramp", name: "Ramp"))]))
        guard case .yourTurn(let request) = state.cardLine(working) else { return #expect(Bool(false), "a request waits on the owner") }
        #expect(request.id == "d-connect", "the earliest request shows, one at a time")
        #expect(DecisionText.ask(request) == "Connect Ramp")

        let mine = WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Buy the domain", state: .inProgress, takenOverBy: "person-preview")
        #expect(state.cardLine(mine) == .yours)

        state.home = .loaded(Home())
        #expect(state.cardLine(WorkItem(id: "c2", ownerEmployeeID: "engineering", title: "Ship", state: .proposed)) == .ready)
        #expect(state.cardLine(WorkItem(id: "c3", ownerEmployeeID: "engineering", title: "Ship", waitCondition: "DNS", state: .waiting)) == .waiting("DNS"))
        let done = WorkItem(id: "c4", ownerEmployeeID: "engineering", title: "Ship", state: .completed, steps: [WorkStep(title: "Ship", state: .done)])
        #expect(state.cardLine(done) == .done && state.stepPosition(done) == nil)
        #expect(state.cardLine(WorkItem(id: "c5", ownerEmployeeID: "engineering", title: "Ship", state: .ready)) == .quiet)
    }

    @Test("Start sends the start request for a plan waiting on the owner, and nothing for one already going")
    func starts() async {
        let server = CardServer()
        let store = await makeStore(server)
        store.send(.startTapped("c1"))
        store.send(.startTapped("c2"))
        await settle("started", until: { store.work.value?.first { $0.id == "c2" }?.state == .ready })
        #expect(await server.started == ["c2"])
        #expect(store.state.cardLine(store.work.value![1]) == .quiet)
    }

    @Test("Stop on a card stops that employee; ⌘. stops the employee of the conversation in view")
    func stops() async {
        let server = CardServer()
        let store = await makeStore(server)
        await settle("growth is working on it", until: { store.state.cardLine(store.work.value![0]) == .working("") })
        store.send(.stopTapped("growth"))
        await settle("stopped", until: { !store.isStopping && store.notice != nil })
        #expect(await server.stops == [EmployeeScope(businessID: "acme", employeeID: "growth")])

        store.send(.placeSelected(.project("p1")))
        #expect(store.state.employeeInView == "growth", "a channel's lead")
        store.send(.threadOpened("c2"))
        #expect(store.state.employeeInView == "engineering", "a thread's owner")
        store.send(.stopTapped)
        for _ in 0..<4_000 where await server.stops.count < 2 { await Task.yield() }
        #expect(await server.stops.last == EmployeeScope(businessID: "acme", employeeID: "engineering"))
    }

    @Test("A request without a work item shows once where it was asked; a work item's only on its card")
    func requestsWhereAsked() {
        var state = Workspace.State(server: localServer)
        state.home = .loaded(Home(needsYou: [
            NeedsYouItem(connect, title: "Ramp"),
            NeedsYouItem(hire, title: "Hire Ada"),
            NeedsYouItem(routine, title: "Weekly check"),
            NeedsYouItem(channel, title: "Create the brief", projectID: "p1")
        ]))
        #expect(state.requests(in: .direct("ops")).map(\.id) == ["d-hire"], "Home is the Chief of Staff's chat")
        #expect(state.requests(in: .direct("growth")).map(\.id) == ["d-routine"])
        #expect(state.requests(in: .project("p1")).map(\.id) == ["d-channel"])
        #expect(state.requests(in: .work("c1")).isEmpty, "the thread shows its request on its card, not as a separate card")
        #expect(state.request(for: WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Buy the domain"))?.id == "d-connect")
    }
}
