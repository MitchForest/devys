import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation

// MARK: - Access and pause

extension Workspace {
    func scope(of employeeID: String, in state: State) -> EmployeeScope? {
        state.snapshot.employees.contains { $0.id == employeeID }
            ? EmployeeScope(businessID: state.businessID, employeeID: employeeID)
            : nil
    }

    func loadAccess(_ employeeID: String, state: State) {
        guard let scope = scope(of: employeeID, in: state) else { return }
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.accessLoaded(employeeID: employeeID, try await runtime.access(scope))))
            } catch let error as DevysHTTPError {
                try store.send(Action(.loadFailed(error, memory: false)))
            }
        }
    }

    /// Applies one grant change, then shows the server's grants again.
    func changeAccess(
        _ employeeID: String,
        state: State,
        change: @escaping @Sendable (RuntimeClient, EmployeeScope) async throws -> Void
    ) {
        guard let scope = scope(of: employeeID, in: state) else { return }
        let runtime = runtime
        store.addTask {
            do {
                try await change(runtime, scope)
                try store.send(Action(.accessLoaded(employeeID: employeeID, try await runtime.access(scope))))
            } catch {
                try store.send(Action(.stopFinished("That access change didn't go through. Try again.")))
            }
        }
    }

    /// Pausing also stops running work; the change shows at once and the team reloads.
    func togglePause(_ employeeID: String, state: inout State) {
        guard let index = state.snapshot.employees.firstIndex(where: { $0.id == employeeID }),
              let scope = scope(of: employeeID, in: state)
        else { return }
        let paused = !state.snapshot.employees[index].paused
        state.snapshot.employees[index].paused = paused
        let runtime = runtime
        let businessID = state.businessID
        store.addTask {
            do {
                try await runtime.setPaused(scope, paused)
            } catch {
                try store.send(Action(.stopFinished("Couldn't \(paused ? "pause" : "resume") that employee. Try again.")))
            }
            try store.send(Action(.detailLoaded(try await runtime.business(businessID))))
        }
    }
}
