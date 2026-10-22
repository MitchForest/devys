import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - Hiring, editing and retiring employees

/// The hire being set up in the Hire sheet: a template first, then the details.
package struct HireDraft: Equatable {
    /// nil while the owner is choosing a template.
    package var template: String?
    package var name = ""
    package var responsibilities = ""
    /// Empty uses the server's default model.
    package var model = ""
    package var isSubmitting = false
    package var error: String?

    package init() {}

    package var canHire: Bool {
        template != nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !responsibilities.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
    }
}

package struct TeamState {
    /// The templates employees are hired from, loaded when the Hire sheet first opens.
    package var roles: Loadable<[RoleTemplate]> = .loading
    package var hiring: HireDraft?

    package init() {}
}

package enum TeamIntent {
    case hireTapped
    case rolesLoaded(Loadable<[RoleTemplate]>)
    case templateChosen(String)
    case hireEdited(HireDraft)
    case hireConfirmed
    case hired(Employee)
    case hireFailed(String)
    case hireCancelled
    case profileSaved(employeeID: String, name: String, responsibilities: String)
    case retireConfirmed(employeeID: String, successorID: String)
    case retired(employeeID: String, successorID: String)
}

extension Workspace {
    func reduceTeam(_ intent: TeamIntent, state: inout State) {
        switch intent {
        case .hireTapped:
            state.team.hiring = HireDraft()
            if state.team.roles.value == nil { loadRoles(state: &state) }
            if state.models.catalog == nil { loadCatalog() }
        case .rolesLoaded(let roles):
            state.team.roles = roles
        case .templateChosen(let id):
            chooseTemplate(id, state: &state)
        case .hireEdited(let draft):
            guard state.team.hiring != nil else { return }
            state.team.hiring = draft
        case .hireConfirmed:
            hire(state: &state)
        case .hired(let employee):
            state.team.hiring = nil
            if !state.snapshot.employees.contains(where: { $0.id == employee.id }) { state.snapshot.employees.append(employee) }
            // A new hire opens in its direct chat.
            reducePlace(.selected(.direct(employee.id)), state: &state)
            refreshTeam(state)
            loadLookPhotos(state)
        case .hireFailed(let message):
            state.team.hiring?.isSubmitting = false
            state.team.hiring?.error = message
        case .hireCancelled:
            state.team.hiring = nil
        case .profileSaved(let employeeID, let name, let responsibilities):
            saveProfile(employeeID, name: name, responsibilities: responsibilities, state: &state)
        case .retireConfirmed(let employeeID, let successorID):
            retire(employeeID, successorID: successorID, state: state)
        case .retired(let employeeID, let successorID):
            // Their open work moved to the successor, whose direct chat opens.
            state.snapshot.employees.removeAll { $0.id == employeeID }
            reducePlace(.selected(.direct(successorID)), state: &state)
            refreshTeam(state)
            loadWork(state)
        }
    }

    func loadRoles(state: inout State) {
        state.team.roles = .loading
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.team(.rolesLoaded(.loaded(try await runtime.roles())))))
            } catch {
                try store.send(Action(.team(.rolesLoaded(.failed("Roles couldn't be loaded. Try again.")))))
            }
        }
    }

    /// A template fills in its name, responsibilities and the default model; all stay editable.
    func chooseTemplate(_ id: String, state: inout State) {
        guard var draft = state.team.hiring else { return }
        let role = state.team.roles.value?.first { $0.id == id }
        draft.template = id
        draft.name = id == "custom" ? "" : role?.name ?? RoleTemplate.displayName(id)
        draft.responsibilities = role?.responsibilities ?? ""
        draft.model = state.models.catalog?.defaults.employee ?? ""
        draft.error = nil
        state.team.hiring = draft
    }

    func hire(state: inout State) {
        guard var draft = state.team.hiring, draft.canHire, let template = draft.template, !state.businessID.isEmpty else { return }
        draft.isSubmitting = true
        draft.error = nil
        state.team.hiring = draft
        let request = Hire(
            template: template,
            name: String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
            responsibilities: String(draft.responsibilities.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000)),
            model: draft.model.isEmpty ? nil : draft.model
        )
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.team(.hired(try await runtime.hire(businessID, request)))))
            } catch let error as DevysHTTPError {
                try store.send(Action(.team(.hireFailed(Self.hireMessage(for: error)))))
            } catch {
                try store.send(Action(.team(.hireFailed("The hire didn't go through. Try again."))))
            }
        }
    }

    /// The change shows at once; the team reloads from the server either way.
    func saveProfile(_ employeeID: String, name: String, responsibilities: String, state: inout State) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let responsibilities = responsibilities.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = state.snapshot.employees.firstIndex(where: { $0.id == employeeID }),
              let scope = scope(of: employeeID, in: state),
              !name.isEmpty, !responsibilities.isEmpty
        else { return }
        let current = state.snapshot.employees[index]
        let change = ProfileChange(
            name: name == current.name ? nil : String(name.prefix(80)),
            responsibilities: responsibilities == current.responsibilities ? nil : String(responsibilities.prefix(2000))
        )
        guard change.name != nil || change.responsibilities != nil else { return }
        state.snapshot.employees[index].name = change.name ?? current.name
        state.snapshot.employees[index].responsibilities = change.responsibilities ?? current.responsibilities
        state.snapshot.employees[index].summary = state.snapshot.employees[index].responsibilities
        let runtime = runtime
        let businessID = state.businessID
        store.addTask {
            do {
                try await runtime.updateProfile(scope, change)
            } catch {
                try store.send(Action(.stopFinished("That change didn't save. Try again.")))
            }
            if let detail = try? await runtime.business(businessID) { try store.send(Action(.teamRefreshed(detail))) }
        }
    }

    /// Open work moves to the successor first; the Head of Operations can't be retired.
    func retire(_ employeeID: String, successorID: String, state: State) {
        guard let employee = state.snapshot.employees.first(where: { $0.id == employeeID }), !employee.isOperations,
              successorID != employeeID, state.snapshot.employees.contains(where: { $0.id == successorID }),
              let scope = scope(of: employeeID, in: state)
        else { return }
        let runtime = runtime
        store.addTask {
            do {
                let successor = try await runtime.retire(scope, successorID)
                try store.send(Action(.team(.retired(employeeID: employeeID, successorID: successor))))
            } catch {
                try store.send(Action(.stopFinished("\(employee.name) couldn't be retired. Try again.")))
            }
        }
    }

    static func hireMessage(for error: DevysHTTPError) -> String {
        switch error {
        case .rejected(status: 400, _): "Give the hire a name and responsibilities."
        case .rejected(status: 403, _): "You can't hire for this business."
        default: "The hire didn't go through. \(message(for: error))"
        }
    }
}

/// How a request reads on an approval card.
enum DecisionText {
    static func title(_ decision: Decision) -> String {
        switch decision.request {
        case .approve(let action, _, let amount, _):
            return amount.map { "Spend \($0.text): \(action)" } ?? action
        case .takeOver(let reason, _):
            return "Sign in / take over: \(reason)"
        case .secret(let name, _, let spend):
            return spend ? "Card: \(name)" : "Secret: \(name)"
        case nil:
            break
        }
        guard decision.capability == "hireEmployee" else { return AccessNames.title(decision.capability) }
        let fields = Dictionary(decision.input.fields, uniquingKeysWith: { first, _ in first })
        let template = fields["template"].map(RoleTemplate.displayName) ?? "Custom"
        let name = fields["name"] ?? template
        return "Hire \(name) · \(template)"
    }

    /// A request as label/value rows: an `askOwner` request in its own words, else its input.
    static func fields(_ decision: Decision) -> [(key: String, value: String)] {
        switch decision.request {
        case .approve(let action, let counterparty, let amount, let renewal):
            return [("Action", action), ("With", counterparty)]
                + (amount.map { [("Amount", $0.text)] } ?? [])
                + (renewal.map { [("Renews", $0)] } ?? [])
        case .takeOver(let reason, let url):
            return [("Do", reason)] + (url.map { [("Site", $0)] } ?? [])
        case .secret(let name, let why, _):
            return [("Name", name), ("Why", why)]
        case nil:
            return decision.input.fields
        }
    }
}
