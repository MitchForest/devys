import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@MainActor
private func settle(_ what: String, until condition: @MainActor () async -> Bool) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(what)")
}

/// One business's team, work, spaces and conversations, as the server keeps them.
private actor TeamServer {
    var employees = BusinessDetail.fixture("acme").employees
    var commitments = [Commitment(id: "c1", ownerEmployeeID: "growth", title: "PR inquiry", state: .inProgress, revision: 3)]
    var spaces = [Space(id: "s1", name: "Launch", purpose: "Ship Acme", leadEmployeeID: "ops")]
    var hires: [Hire] = []
    var profiles: [(String, ProfileChange)] = []
    var retirements: [(String, String)] = []
    var changes: [(String, CommitmentChange)] = []
    var tasks: [NewTask] = []

    func detail() -> BusinessDetail {
        BusinessDetail(business: Business(id: "acme", name: "Acme"), employees: employees, artifacts: [])
    }

    func hire(_ request: Hire) throws -> Employee {
        hires.append(request)
        guard let name = request.name, !name.isEmpty else { throw DevysHTTPError.rejected(status: 400, message: "") }
        let employee = Employee(id: "e\(hires.count)", name: name, role: request.responsibilities ?? "", template: request.template, model: request.model ?? "claude-opus-5-5")
        employees.append(employee)
        return employee
    }

    func profile(_ id: String, _ change: ProfileChange) {
        profiles.append((id, change))
        guard let index = employees.firstIndex(where: { $0.id == id }) else { return }
        if let name = change.name { employees[index].name = name }
        if let role = change.responsibilities { employees[index].role = role }
    }

    func retire(_ id: String, _ successor: String) -> String {
        retirements.append((id, successor))
        employees.removeAll { $0.id == id }
        commitments = commitments.map { item in
            item.ownerEmployeeID == id ? Commitment(id: item.id, ownerEmployeeID: successor, title: item.title, state: item.state, revision: item.revision + 1) : item
        }
        return successor
    }

    func update(_ id: String, _ change: CommitmentChange) throws -> Commitment {
        changes.append((id, change))
        guard let index = commitments.firstIndex(where: { $0.id == id }), commitments[index].revision == change.expectedRevision else {
            throw DevysHTTPError.rejected(status: 409, message: "changed")
        }
        let item = commitments[index]
        let updated = Commitment(
            id: id,
            ownerEmployeeID: change.owner ?? item.ownerEmployeeID,
            title: item.title,
            state: change.state ?? item.state,
            revision: item.revision + 1
        )
        commitments[index] = updated
        return updated
    }

    func create(_ task: NewTask) -> Commitment {
        tasks.append(task)
        let item = Commitment(id: "c\(commitments.count + 1)", ownerEmployeeID: task.owner, title: task.title)
        commitments.append(item)
        if let space = task.spaceId, let index = spaces.firstIndex(where: { $0.id == space }) {
            let old = spaces[index]
            spaces[index] = Space(id: old.id, name: old.name, purpose: old.purpose, leadEmployeeID: old.leadEmployeeID, items: old.items + [SpaceItem(id: "i\(tasks.count)", kind: .commitment, ref: item.id)])
        }
        return item
    }
}

nonisolated private let roles = [
    RoleTemplate(id: "engineering", name: "Engineering", summary: "Builds.", responsibilities: "Owns the code and releases.", capabilities: ["read", "write"]),
    RoleTemplate(id: "custom", name: "Custom", summary: "Anything.", responsibilities: "", capabilities: [])
]

@MainActor
@Suite("Team, spaces and tasks")
struct TeamFeatureTests {
    private func makeStore(_ server: TeamServer) async -> StoreOf<Workspace> {
        let store: StoreOf<Workspace> = withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { _ in await server.detail() },
                roles: { roles },
                hire: { _, request in try await server.hire(request) },
                updateProfile: { scope, change in await server.profile(scope.employeeID, change) },
                retire: { scope, successor in await server.retire(scope.employeeID, successor) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] },
                models: { .fixture },
                work: { _ in await server.commitments },
                createCommitment: { _, task in await server.create(task) },
                updateCommitment: { _, id, change in try await server.update(id, change) },
                spaces: { _ in await server.spaces }
            )
            $0.continuousClock = ContinuousClock()
            $0.uuid = .incrementing
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
        await settle("team and work", until: { store.operationsScope != nil && store.work.value != nil })
        return store
    }

    @Test("Hiring: choose a template, adjust the details, and the new employee opens")
    func hires() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.hireTapped)
        await settle("roles and catalog", until: { store.team.roles.value == roles && store.models.catalog != nil })
        #expect(store.team.hiring?.canHire == false)
        store.send(.templateChosen("engineering"))
        guard var draft = store.team.hiring else { return #expect(Bool(false), "the sheet stays open") }
        #expect(draft.name == "Engineering" && draft.responsibilities == "Owns the code and releases.")
        #expect(draft.model == ModelCatalog.fixture.defaults.employee)
        draft.name = "Ada"
        draft.model = "gpt-6.1-sol"
        store.send(.hireEdited(draft))
        store.send(.hireConfirmed)
        await settle("hired", until: { store.team.hiring == nil })
        #expect(await server.hires == [Hire(template: "engineering", name: "Ada", responsibilities: "Owns the code and releases.", model: "gpt-6.1-sol")])
        #expect(store.snapshot.employees.last?.name == "Ada")
        #expect(store.page == .employee("e1"))
    }

    @Test("A custom hire starts blank and can't be sent without a name")
    func customHire() async {
        let store = await makeStore(TeamServer())
        store.send(.hireTapped)
        await settle("roles", until: { store.team.roles.value != nil })
        store.send(.templateChosen("custom"))
        #expect(store.team.hiring?.name.isEmpty == true && store.team.hiring?.responsibilities.isEmpty == true)
        #expect(store.team.hiring?.canHire == false)
        store.send(.hireConfirmed)
        #expect(store.team.hiring?.isSubmitting == false)
    }

    @Test("Editing a profile shows at once and sends only what changed")
    func editsProfile() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.profileSaved("growth", name: "Growth", responsibilities: "  PR and paid social  "))
        #expect(store.snapshot.employees.first { $0.id == "growth" }?.role == "PR and paid social")
        await settle("saved", until: { await server.profiles.count == 1 })
        let change = await server.profiles.first?.1
        #expect(change == ProfileChange(responsibilities: "PR and paid social"))
    }

    @Test("Retiring hands open work to the successor and opens their page; Operations can't be retired")
    func retires() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.pageSelected(.employee("growth")))
        store.send(.retireConfirmed("ops", successor: "growth"))
        store.send(.retireConfirmed("growth", successor: "engineering"))
        await settle("retired", until: { !store.snapshot.employees.contains { $0.id == "growth" } })
        let retirements = await server.retirements
        #expect(retirements.count == 1 && retirements.first?.0 == "growth" && retirements.first?.1 == "engineering")
        #expect(store.page == .employee("engineering"))
        await settle("work reassigned", until: { store.work.value?.first?.ownerEmployeeID == "engineering" })
    }

    @Test("Mentions match whole names, longest first, in team order")
    func mentionParsing() {
        let team = [
            Employee(id: "a", name: "Growth", role: ""),
            Employee(id: "b", name: "Growth Lead", role: ""),
            Employee(id: "c", name: "Head of Operations", role: "")
        ]
        #expect(Mentions.recipients(in: "@growth lead and @Head of Operations", team: team) == ["b", "c"])
        #expect(Mentions.recipients(in: "@Growth and @Growth Lead", team: team) == ["a", "b"])
        #expect(Mentions.recipients(in: "no mentions", team: team).isEmpty)
    }

    @Test("New task from a space carries the space; from an employee, its owner")
    func newTasks() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.newTaskTapped(space: "s1"))
        guard var draft = store.newTask else { return #expect(Bool(false), "the sheet opens") }
        #expect(draft.spaceID == "s1" && draft.ownerID == "ops")
        draft.title = "Book the domain"
        draft.objective = "acme.example or similar"
        store.send(.taskEdited(draft))
        store.send(.taskConfirmed)
        await settle("created", until: { store.newTask == nil && store.spaces.value?.first?.refs(.commitment) == ["c2"] })
        let task = await server.tasks.first
        #expect(task == NewTask(title: "Book the domain", owner: "ops", objective: "acme.example or similar", spaceId: "s1"))

        store.send(.newTaskTapped(owner: "engineering"))
        #expect(store.newTask?.ownerID == "engineering" && store.newTask?.spaceID == nil)
        store.send(.taskCancelled)
        #expect(store.newTask == nil)
    }

    @Test("Reassigning sends the new owner, ready, at the revision on screen")
    func reassigns() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.reassigned("c1", to: "growth"))
        store.send(.reassigned("c1", to: "engineering"))
        await settle("reassigned", until: { store.work.value?.first?.ownerEmployeeID == "engineering" })
        let changes = await server.changes
        #expect(changes.count == 1)
        #expect(changes.first?.1 == CommitmentChange(expectedRevision: 3, owner: "engineering", state: .ready))
        #expect(store.work.value?.first?.state == .ready)
    }

    @Test("A proposed hire reads as the hire it asks for")
    func hireDecision() {
        let decision = Decision(
            id: "d1",
            employeeID: "ops",
            capability: "hireEmployee",
            input: .object(["template": .string("growth"), "name": .string("Paid social"), "responsibilities": .string("Ads")])
        )
        #expect(DecisionText.title(decision) == "Hire Paid social · Growth")
        #expect(DecisionText.title(Decision(id: "d2", employeeID: "ops", capability: "driveCreate", input: .null)) == "Create Drive files")
    }
}
