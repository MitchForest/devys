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

/// The routines route as the server keeps it: pause only an active routine, resume only a paused
/// one, and activate a proposal only through its decision.
private actor RoutineServer {
    var routines = [
        Routine(id: "r1", employeeID: "growth", title: "Weekly bookings report", state: .active, nextRunAt: "2026-10-26T14:00:00.000Z"),
        Routine(id: "r2", employeeID: "growth", projectID: "p1", title: "Supplier replies", state: .proposed)
    ]
    var home = Home(needsYou: [
        NeedsYouItem(
            Decision(id: "d1", employeeID: "growth", capability: "routineActivate", input: .object(["ref": .string("r2"), "revision": .number(1)])),
            title: "Supplier replies",
            projectID: "p1",
            routine: Routine(id: "r2", employeeID: "growth", projectID: "p1", title: "Supplier replies", state: .proposed)
        )
    ])
    var requests: [String] = []
    var answers: [(String, Bool)] = []

    func setPaused(_ id: String, _ paused: Bool) throws -> Routine {
        requests.append("\(id):\(paused ? "pause" : "resume")")
        guard let index = routines.firstIndex(where: { $0.id == id }), routines[index].state == (paused ? .active : .paused) else {
            throw DevysHTTPError.rejected(status: 409, message: "Only a paused routine can be resumed; a proposed one is activated by your decision")
        }
        routines[index] = changed(routines[index], to: paused ? .paused : .active)
        return routines[index]
    }

    func answer(_ id: String, _ approve: Bool) {
        answers.append((id, approve))
        guard let routine = home.needsYou.first(where: { $0.id == id })?.routine else { return }
        home = home.answering(id)
        if approve, let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = changed(routines[index], to: .active)
        }
    }

    private func changed(_ routine: Routine, to state: RoutineState) -> Routine {
        Routine(
            id: routine.id,
            employeeID: routine.employeeID,
            projectID: routine.projectID,
            title: routine.title,
            state: state,
            revision: routine.revision,
            nextRunAt: state == .active ? "2026-10-26T14:00:00.000Z" : nil
        )
    }
}

@MainActor
@Suite("Routines")
struct RoutineFeatureTests {
    private func makeStore(_ server: RoutineServer) -> StoreOf<Workspace> {
        withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] },
                answer: { _, id, approve in await server.answer(id, approve) },
                projects: { _ in [Project(id: "p1", name: "Launch")] },
                home: { _ in await server.home },
                routines: { _ in await server.routines },
                setRoutinePaused: { _, id, paused in try await server.setPaused(id, paused) }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
    }

    private func state(_ store: StoreOf<Workspace>, _ id: String) -> RoutineState? {
        store.state.routine(id)?.state
    }

    @Test("Pausing and resuming an active routine shows what the server saved")
    func pausesAndResumes() async {
        let server = RoutineServer()
        let store = makeStore(server)
        await settle("routines", until: { store.routines.value?.count == 2 })
        store.send(.routinePauseTapped("r1"))
        await settle("paused", until: { state(store, "r1") == .paused })
        #expect(store.state.routine("r1")?.nextRunAt == nil)
        store.send(.routineResumeTapped("r1"))
        await settle("resumed", until: { state(store, "r1") == .active })
        #expect(store.state.routine("r1")?.nextRunAt != nil)
        // Pausing what is already paused, or resuming what runs, sends nothing.
        store.send(.routineResumeTapped("r1"))
        for _ in 0..<500 { await Task.yield() }
        #expect(await server.requests == ["r1:pause", "r1:resume"])
    }

    @Test("A proposed routine is not resumed by hand; approving its proposal in Needs you activates it")
    func approvesProposal() async {
        let server = RoutineServer()
        let store = makeStore(server)
        await settle("home", until: { store.home.value?.needsYou.first?.routine?.id == "r2" && store.routines.value != nil })
        store.send(.routineResumeTapped("r2"))
        for _ in 0..<500 { await Task.yield() }
        #expect(await server.requests.isEmpty)
        store.send(.decisionAnswered("d1", approve: true))
        #expect(store.home.value?.needsYou.isEmpty == true)
        await settle("activated", until: { state(store, "r2") == .active })
        let answers = await server.answers
        #expect(answers.count == 1 && answers.first?.0 == "d1" && answers.first?.1 == true)
    }

    @Test("Waiting work says until when it looks again; a routine opens as a read-only layer")
    func texts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tomorrow = now.addingTimeInterval(86_400)
        #expect(RoutineText.upcoming(tomorrow, now: now).hasPrefix("Tomorrow "))
        #expect(RoutineText.upcoming(now, now: now).hasPrefix("Today "))
        let waiting = WorkItem(id: "w", ownerEmployeeID: "e", title: "t", waitCondition: "the supplier", wakeAt: "2026-10-22T14:00:00.000Z", state: .waiting)
        #expect(RoutineText.waiting(waiting)?.hasPrefix("waiting on the supplier until ") == true)
        #expect(RoutineText.waiting(WorkItem(id: "w", ownerEmployeeID: "e", title: "t", wakeAt: "2026-10-22T14:00:00.000Z"))?.hasPrefix("waiting until ") == true)
        #expect(RoutineText.notify(.whenFound) == "Posts only when something needs attention")
        #expect(Records.open(.workRoutine("r1")) == .layer(.routine("r1")) && Layer.routine("r1").ref == .workRoutine("r1"))
    }
}
