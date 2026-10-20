import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - Models and spend

/// The models employees can use and what each has spent.
package struct EmployeeModels {
    /// Loaded when an employee page first shows.
    package var catalog: ModelCatalog?
    /// Spend by employee id for employees other than Operations, whose spend comes with its status.
    package var usage: [String: RuntimeUsage] = [:]
    /// Why the last model change for an employee didn't go through, by employee id.
    package var errors: [String: String] = [:]

    package init() {}
}

package enum ModelIntent {
    case requested(employeeID: String)
    /// Money: every employee's spend.
    case allUsageRequested
    case catalogLoaded(ModelCatalog)
    case usageLoaded(employeeID: String, RuntimeUsage?)
    case selected(employeeID: String, model: String)
    case saved(employeeID: String, model: String)
    case saveFailed(employeeID: String, previous: String, message: String)
}

extension Workspace.State {
    /// What an employee's runtime has spent, when it has reported any.
    package func usage(of employeeID: String) -> RuntimeUsage? {
        employeeID == operations?.id ? status.value?.state.usage : models.usage[employeeID]
    }
}

extension Workspace {
    func reduceModel(_ intent: ModelIntent, state: inout State) {
        switch intent {
        case .requested(let employeeID):
            if state.models.catalog == nil { loadCatalog() }
            loadUsage(employeeID, state: state)
        case .allUsageRequested:
            if state.models.catalog == nil { loadCatalog() }
            for employee in state.snapshot.employees { loadUsage(employee.id, state: state) }
        case .catalogLoaded(let catalog):
            state.models.catalog = catalog
        case .usageLoaded(let employeeID, let usage):
            state.models.usage[employeeID] = usage
        case .selected(let employeeID, let model):
            selectModel(model, for: employeeID, state: &state)
        case .saved(let employeeID, let model):
            setModel(model, for: employeeID, state: &state)
        case .saveFailed(let employeeID, let previous, let message):
            setModel(previous, for: employeeID, state: &state)
            state.models.errors[employeeID] = message
        }
    }

    func loadCatalog() {
        let runtime = runtime
        store.addTask {
            if let catalog = try? await runtime.models() { try store.send(Action(.model(.catalogLoaded(catalog)))) }
        }
    }

    /// Operations' spend arrives with its status; anyone else's is read when their page opens.
    func loadUsage(_ employeeID: String, state: State) {
        guard employeeID != state.operations?.id, let scope = scope(of: employeeID, in: state) else { return }
        let runtime = runtime
        store.addTask {
            guard let status = try? await runtime.status(scope) else { return }
            try store.send(Action(.model(.usageLoaded(employeeID: employeeID, status.state.usage))))
        }
    }

    /// The change shows at once; a refusal puts the previous model back and says why.
    func selectModel(_ model: String, for employeeID: String, state: inout State) {
        guard let previous = state.snapshot.employees.first(where: { $0.id == employeeID })?.model,
              previous != model,
              let scope = scope(of: employeeID, in: state)
        else { return }
        setModel(model, for: employeeID, state: &state)
        state.models.errors[employeeID] = nil
        let runtime = runtime
        let session = session
        store.addTask {
            do {
                let saved = try await runtime.setModel(scope, model)
                try store.send(Action(.model(.saved(employeeID: employeeID, model: saved))))
            } catch let error as DevysHTTPError {
                if error == .unauthorized { await session.expire() }
                try store.send(Action(.model(.saveFailed(employeeID: employeeID, previous: previous, message: Self.modelMessage(for: error)))))
            } catch {
                try store.send(Action(.model(.saveFailed(
                    employeeID: employeeID,
                    previous: previous,
                    message: "The model didn't change. Try again."
                ))))
            }
        }
    }

    func setModel(_ model: String, for employeeID: String, state: inout State) {
        guard let index = state.snapshot.employees.firstIndex(where: { $0.id == employeeID }) else { return }
        state.snapshot.employees[index].model = model
    }

    static func modelMessage(for error: DevysHTTPError) -> String {
        switch error {
        case .rejected(status: 400, _): "That model isn't available on this server."
        case .rejected(status: 403, _): "You can't change this employee's model."
        default: "The model didn't change. \(message(for: error))"
        }
    }
}
