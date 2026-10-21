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

/// One business's team, work and projects, as the server keeps them.
private actor TeamServer {
    var employees = BusinessDetail.fixture("acme").employees
    var workItems = [WorkItem(id: "c1", ownerEmployeeID: "growth", title: "PR inquiry", state: .inProgress, revision: 3)]
    var projects = [Project(id: "p1", name: "Launch", goal: "Ship Acme", leadEmployeeID: "ops")]
    var hires: [Hire] = []
    var profiles: [(String, ProfileChange)] = []
    var retirements: [(String, String)] = []
    var changes: [(String, WorkItemChange)] = []
    var newItems: [NewWorkItem] = []

    func detail() -> BusinessDetail {
        BusinessDetail(business: Business(id: "acme", name: "Acme"), employees: employees, artifacts: [])
    }

    func hire(_ request: Hire) throws -> Employee {
        hires.append(request)
        guard let name = request.name, !name.isEmpty else { throw DevysHTTPError.rejected(status: 400, message: "") }
        let employee = Employee(id: "e\(hires.count)", name: name, responsibilities: request.responsibilities ?? "", template: request.template, model: request.model ?? "claude-opus-5-5")
        employees.append(employee)
        return employee
    }

    func profile(_ id: String, _ change: ProfileChange) {
        profiles.append((id, change))
        guard let index = employees.firstIndex(where: { $0.id == id }) else { return }
        if let name = change.name { employees[index].name = name }
        if let role = change.responsibilities { employees[index].responsibilities = role }
    }

    func retire(_ id: String, _ successor: String) -> String {
        retirements.append((id, successor))
        employees.removeAll { $0.id == id }
        workItems = workItems.map { item in
            item.ownerEmployeeID == id ? WorkItem(id: item.id, ownerEmployeeID: successor, title: item.title, state: item.state, revision: item.revision + 1) : item
        }
        return successor
    }

    func update(_ id: String, _ change: WorkItemChange) throws -> WorkItem {
        changes.append((id, change))
        guard let index = workItems.firstIndex(where: { $0.id == id }), workItems[index].revision == change.expectedRevision else {
            throw DevysHTTPError.rejected(status: 409, message: "changed")
        }
        let item = workItems[index]
        let value = { (value: WorkItemChange.Value?, old: String?) -> String? in
            switch value {
            case .set(let text): text
            case .clear: nil
            case nil: old
            }
        }
        let updated = WorkItem(
            id: id,
            ownerEmployeeID: change.owner ?? item.ownerEmployeeID,
            title: item.title,
            nextAction: change.nextAction ?? item.nextAction,
            waitCondition: value(change.waitCondition, item.waitCondition),
            dueAt: value(change.dueAt, item.dueAt),
            state: change.state ?? item.state,
            revision: item.revision + 1,
            takenOverBy: item.takenOverBy
        )
        workItems[index] = updated
        return updated
    }

    /// Someone else changes the item meanwhile.
    func touch(_ id: String) {
        guard let index = workItems.firstIndex(where: { $0.id == id }) else { return }
        let item = workItems[index]
        workItems[index] = WorkItem(
            id: id, ownerEmployeeID: item.ownerEmployeeID, title: item.title, nextAction: item.nextAction,
            waitCondition: item.waitCondition, dueAt: item.dueAt, state: item.state, revision: item.revision + 1, takenOverBy: item.takenOverBy
        )
    }

    func add(_ item: WorkItem) { workItems.append(item) }

    func create(_ newItem: NewWorkItem) -> WorkItem {
        newItems.append(newItem)
        let item = WorkItem(id: "c\(workItems.count + 1)", ownerEmployeeID: newItem.owner, title: newItem.title, projectID: newItem.projectID)
        workItems.append(item)
        return item
    }
}

nonisolated private let roles = [
    RoleTemplate(id: "engineering", name: "Engineering", summary: "Builds.", responsibilities: "Owns the code and releases.", capabilities: ["read", "write"]),
    RoleTemplate(id: "custom", name: "Custom", summary: "Anything.", responsibilities: "", capabilities: [])
]

@MainActor
@Suite("Team, projects and work items")
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
                models: { .golden },
                work: { _ in await server.workItems },
                createWorkItem: { _, newItem in await server.create(newItem) },
                updateWorkItem: { _, id, change in try await server.update(id, change) },
                projects: { _ in await server.projects }
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
        #expect(draft.model == ModelCatalog.golden.defaults.employee)
        draft.name = "Ada"
        draft.model = "gpt-6.1-sol"
        store.send(.hireEdited(draft))
        store.send(.hireConfirmed)
        await settle("hired", until: { store.team.hiring == nil })
        #expect(await server.hires == [Hire(template: "engineering", name: "Ada", responsibilities: "Owns the code and releases.", model: "gpt-6.1-sol")])
        #expect(store.snapshot.employees.last?.name == "Ada")
        #expect(store.place == .direct("e1"))
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
        #expect(store.snapshot.employees.first { $0.id == "growth" }?.responsibilities == "PR and paid social")
        await settle("saved", until: { await server.profiles.count == 1 })
        let change = await server.profiles.first?.1
        #expect(change == ProfileChange(responsibilities: "PR and paid social"))
    }

    @Test("Retiring hands open work to the successor and opens their direct chat; Operations can't be retired")
    func retires() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.message("growth"))
        store.send(.retireConfirmed("ops", successor: "growth"))
        store.send(.retireConfirmed("growth", successor: "engineering"))
        await settle("retired", until: { !store.snapshot.employees.contains { $0.id == "growth" } })
        let retirements = await server.retirements
        #expect(retirements.count == 1 && retirements.first?.0 == "growth" && retirements.first?.1 == "engineering")
        #expect(store.place == .direct("engineering"))
        await settle("work reassigned", until: { store.work.value?.first?.ownerEmployeeID == "engineering" })
    }

    @Test("Mentions match whole names, longest first, in team order")
    func mentionParsing() {
        let team = [
            Employee(id: "a", name: "Growth", responsibilities: "", model: "claude-opus-5-5"),
            Employee(id: "b", name: "Growth Lead", responsibilities: "", model: "claude-opus-5-5"),
            Employee(id: "c", name: "Head of Operations", responsibilities: "", model: "claude-opus-5-5")
        ]
        #expect(Mentions.recipients(in: "@growth lead and @Head of Operations", team: team) == ["b", "c"])
        #expect(Mentions.recipients(in: "@Growth and @Growth Lead", team: team) == ["a", "b"])
        #expect(Mentions.recipients(in: "no mentions", team: team).isEmpty)
    }

    @Test("New work item from a project carries the project and opens its thread; from an employee, its owner")
    func newTasks() async {
        let server = TeamServer()
        let store = await makeStore(server)
        store.send(.placeSelected(.project("p1")))
        store.send(.newWorkItemTapped(project: "p1"))
        guard var draft = store.newWorkItem else { return #expect(Bool(false), "the sheet opens") }
        #expect(draft.projectID == "p1" && draft.ownerID == "ops")
        draft.title = "Book the domain"
        draft.objective = "acme.example or similar"
        store.send(.workItemEdited(draft))
        store.send(.workItemConfirmed)
        await settle("created", until: { store.newWorkItem == nil && store.place == .thread("c2") })
        #expect(store.history == [.project("p1")])
        #expect(store.work.value?.last?.projectID == "p1")
        let newItem = await server.newItems.first
        #expect(newItem == NewWorkItem(title: "Book the domain", owner: "ops", objective: "acme.example or similar", projectID: "p1"))

        store.send(.newWorkItemTapped(owner: "engineering"))
        #expect(store.newWorkItem?.ownerID == "engineering" && store.newWorkItem?.projectID == nil)
        store.send(.workItemCancelled)
        #expect(store.newWorkItem == nil)
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
        #expect(changes.first?.1 == WorkItemChange(expectedRevision: 3, owner: "engineering", state: .ready))
        #expect(store.work.value?.first?.state == .ready)
    }

    @Test("The work card is read-only until taken over; Edit saves only what changed, at the revision on screen")
    func editsPlan() async {
        let server = TeamServer()
        await server.add(WorkItem(id: "c9", ownerEmployeeID: "growth", title: "Press kit", nextAction: "Draft it", state: .inProgress, revision: 1, takenOverBy: "person-preview"))
        let store = await makeStore(server)
        await settle("account and work", until: { store.account != nil && store.work.value?.count == 2 })

        store.send(.planEditTapped("c1"))
        #expect(store.workPlan == nil, "work the owner hasn't taken over stays read-only")

        store.send(.planEditTapped("c9"))
        #expect(store.workPlan?.workItemID == "c9" && store.workPlan?.nextAction == "Draft it" && store.workPlan?.hasDue == false)
        store.send(.planSaveTapped)
        #expect(store.workPlan == nil, "nothing changed closes the editor")
        #expect(await server.changes.isEmpty)

        store.send(.planEditTapped("c9"))
        guard var draft = store.workPlan else { return #expect(Bool(false), "the editor opens") }
        draft.nextAction = "  Send it to press  "
        draft.waiting = "Logo files"
        store.send(.planEdited(draft))
        await server.touch("c9")
        store.send(.planSaveTapped)
        await settle("conflict", until: { store.workPlan?.error != nil && store.work.value?[1].revision == 2 })
        #expect(store.workPlan?.nextAction == "  Send it to press  ", "the draft stays to save again")

        store.send(.planSaveTapped)
        await settle("saved", until: { store.workPlan == nil && store.work.value?[1].nextAction == "Send it to press" })
        let change = await server.changes.last?.1
        #expect(change == WorkItemChange(expectedRevision: 2, nextAction: "Send it to press", waitCondition: .set("Logo files")))
        #expect(store.work.value?[1].waitCondition == "Logo files")

        store.send(.planEditTapped("c9"))
        store.send(.takeoverToggled("c9"))
        #expect(store.workPlan == nil, "handing back closes the editor")
    }

    @Test("A plan's due date is saved as the end of that day, and only when the day changes")
    func planDue() {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let item = WorkItem(id: "c1", ownerEmployeeID: "ops", title: "T", dueAt: ServerDate.format(noon), revision: 4)
        var draft = WorkPlanDraft(item)
        #expect(draft.hasDue && draft.change(from: item) == nil)
        draft.due = calendar.date(byAdding: .hour, value: 3, to: noon)!
        #expect(draft.change(from: item) == nil, "the same day is no change")
        draft.due = calendar.date(byAdding: .day, value: 1, to: noon)!
        let endOfNextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59))!
        #expect(draft.change(from: item) == WorkItemChange(expectedRevision: 4, dueAt: .set(ServerDate.format(endOfNextDay))))
        draft.hasDue = false
        #expect(draft.change(from: item) == WorkItemChange(expectedRevision: 4, dueAt: .clear))
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
