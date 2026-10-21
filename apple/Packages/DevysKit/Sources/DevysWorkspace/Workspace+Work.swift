import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - Work, decisions, projects, apps and Home

/// Everything the sidebar and the permanent views read, loaded together every tick.
package struct WorkRecords: Sendable {
    package var work: [Commitment]
    package var decisions: [Decision]
    package var projects: [Project]
    package var home: Home
    package var apps: [AppEntry]

    package init(work: [Commitment], decisions: [Decision], projects: [Project], home: Home, apps: [AppEntry]) {
        self.work = work
        self.decisions = decisions
        self.projects = projects
        self.home = home
        self.apps = apps
    }
}

/// The New project sheet: the fields live in the sheet; this is what the server said.
package struct ProjectSheet: Equatable {
    package var isSubmitting = false
    package var error: String?

    package init() {}
}

package enum ProjectIntent {
    case newTapped
    case sheetDismissed
    case createTapped(ProjectChange)
    case created(Project)
    case createFailed
    /// The overview's edit form, saved as one change.
    case updated(projectID: String, ProjectChange)
    /// Keeps a page or file on the project's overview; the record stays in its app.
    case itemAdded(projectID: String, ProjectItem.Kind, ref: String)
    case itemRemoved(projectID: String, itemID: String)
}

extension Workspace {
    func reduceWork(_ intent: Intent, state: inout State) {
        switch intent {
        case .workLoaded(let businessID, let records):
            guard businessID == state.businessID else { return }
            state.work = .loaded(records.work)
            state.decisions = .loaded(records.decisions)
            state.projects = .loaded(records.projects)
            state.home = .loaded(records.home)
            state.apps = .loaded(records.apps)
        case .decisionAnswered(let decisionID, let approve):
            answer(decisionID, approve: approve, state: &state)
        case .commitmentStateSet(let commitmentID, let target):
            setState(commitmentID, target, state: state)
        case .takeoverToggled(let commitmentID):
            toggleTakeover(commitmentID, state: state)
        default:
            break
        }
    }

    func reduceProject(_ intent: ProjectIntent, state: inout State) {
        switch intent {
        case .newTapped:
            state.newProject = ProjectSheet()
        case .sheetDismissed:
            state.newProject = nil
        case .createTapped(let project):
            createProject(project, state: &state)
        case .created(let project):
            state.newProject = nil
            reducePlace(.selected(.project(project.id)), state: &state)
        case .createFailed:
            state.newProject?.isSubmitting = false
            state.newProject?.error = "The project couldn't be created."
        case .updated(let projectID, let change):
            changeWork(state, failure: "The project couldn't be saved.") { runtime, businessID in
                try await runtime.updateProject(businessID, projectID, change)
            }
        case .itemAdded(let projectID, let kind, let ref):
            changeWork(state, failure: "That couldn't be added to the project.") { runtime, businessID in
                try await runtime.addToProject(businessID, projectID, kind, ref)
            }
        case .itemRemoved(let projectID, let itemID):
            changeWork(state, failure: "That couldn't be removed.") { runtime, businessID in
                try await runtime.removeFromProject(businessID, projectID, itemID)
            }
        }
    }

    /// A project needs a name; it opens once the server has it.
    func createProject(_ project: ProjectChange, state: inout State) {
        var project = project
        project.name = String(project.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !project.name.isEmpty, !state.businessID.isEmpty, state.newProject?.isSubmitting != true else { return }
        state.newProject = ProjectSheet()
        state.newProject?.isSubmitting = true
        let request = project
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            let created: Project
            do {
                created = try await runtime.createProject(businessID, request)
            } catch {
                try store.send(Action(.project(.createFailed)))
                return
            }
            try await reloadWork(runtime, businessID)
            try store.send(Action(.project(.created(created))))
        }
    }

    func loadWork(_ state: State) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask { try await reloadWork(runtime, businessID) }
    }

    func answer(_ decisionID: String, approve: Bool, state: inout State) {
        if var pending = state.decisions.value {
            pending.removeAll { $0.id == decisionID }
            state.decisions = .loaded(pending)
        }
        changeWork(state, failure: "That request was already answered or has expired.") { runtime, businessID in
            try await runtime.answer(businessID, decisionID, approve)
        }
    }

    func setState(_ commitmentID: String, _ target: CommitmentState, state: State) {
        guard let item = state.work.value?.first(where: { $0.id == commitmentID }), item.state != target else { return }
        updateCommitment(commitmentID, CommitmentChange(expectedRevision: item.revision, state: target), state: state)
    }

    func toggleTakeover(_ commitmentID: String, state: State) {
        guard let item = state.work.value?.first(where: { $0.id == commitmentID }) else { return }
        let takeOver = item.takenOverBy == nil
        changeWork(state, failure: "Couldn't change who handles that work.") { runtime, businessID in
            try await runtime.setTakeover(businessID, commitmentID, takeOver)
        }
    }

    /// Applies one change to work, a decision or a project, then shows the server's records again.
    func changeWork(
        _ state: State,
        failure: String,
        change: @escaping @Sendable (RuntimeClient, String) async throws -> Void
    ) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            do {
                try await change(runtime, businessID)
            } catch {
                try store.send(Action(.stopFinished(failure)))
            }
            try await reloadWork(runtime, businessID)
        }
    }

    func reloadWork(_ runtime: RuntimeClient, _ businessID: String) async throws {
        // A failed reload keeps what's on screen; the next tick tries again.
        async let work = runtime.work(businessID)
        async let decisions = runtime.decisions(businessID)
        async let projects = runtime.projects(businessID)
        async let home = runtime.home(businessID)
        async let apps = runtime.apps(businessID)
        guard let records = try? await WorkRecords(work: work, decisions: decisions, projects: projects, home: home, apps: apps) else { return }
        try store.send(Action(.workLoaded(businessID: businessID, records)))
    }
}
