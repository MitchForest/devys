import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

// MARK: - Creating and changing work

/// The task being written in the New task sheet.
package struct TaskDraft: Equatable {
    package var title = ""
    package var ownerID: String
    package var objective = ""
    package var hasDue = false
    package var due: Date
    /// Created from a space, the task also shows there.
    package var spaceID: String?
    package var isSubmitting = false
    package var error: String?

    package init(ownerID: String, due: Date, spaceID: String? = nil) {
        self.ownerID = ownerID
        self.due = due
        self.spaceID = spaceID
    }

    package var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ownerID.isEmpty && !isSubmitting
    }

    package var task: NewTask {
        let objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewTask(
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
            owner: ownerID,
            objective: objective.isEmpty ? nil : String(objective.prefix(4000)),
            dueAt: hasDue ? due.formatted(.iso8601) : nil,
            spaceId: spaceID
        )
    }
}

package enum TaskIntent {
    /// From Work (no presets), an employee (its owner) or a space (its space).
    case newTaskTapped(ownerID: String?, spaceID: String?)
    case edited(TaskDraft)
    case confirmed
    case created(Commitment)
    case failed(String)
    case cancelled
    /// Any field change on a work item's page, at the revision on screen.
    case changed(commitmentID: String, CommitmentChange)
    /// Hands the work to another employee, ready to start.
    case reassigned(commitmentID: String, ownerID: String)
}

extension Workspace {
    func reduceTask(_ intent: TaskIntent, state: inout State) {
        switch intent {
        case .newTaskTapped(let ownerID, let spaceID):
            guard let owner = ownerID ?? state.operations?.id else { return }
            state.newTask = TaskDraft(ownerID: owner, due: Date.now.addingTimeInterval(86_400), spaceID: spaceID)
        case .edited(let draft):
            guard state.newTask != nil else { return }
            state.newTask = draft
        case .confirmed:
            createTask(state: &state)
        case .created:
            state.newTask = nil
        case .failed(let message):
            state.newTask?.isSubmitting = false
            state.newTask?.error = message
        case .cancelled:
            state.newTask = nil
        case .changed(let commitmentID, let change):
            updateCommitment(commitmentID, change, state: state)
        case .reassigned(let commitmentID, let ownerID):
            guard let item = state.work.value?.first(where: { $0.id == commitmentID }), item.ownerEmployeeID != ownerID else { return }
            updateCommitment(commitmentID, .reassign(item, to: ownerID), state: state)
        }
    }

    func createTask(state: inout State) {
        guard var draft = state.newTask, draft.canCreate, !state.businessID.isEmpty else { return }
        draft.isSubmitting = true
        draft.error = nil
        state.newTask = draft
        let task = draft.task
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            let created: Commitment
            do {
                created = try await runtime.createCommitment(businessID, task)
            } catch {
                try store.send(Action(.task(.failed("The task couldn't be saved. Try again."))))
                return
            }
            try store.send(Action(.task(.created(created))))
            try await reloadWork(runtime, businessID)
        }
    }

    func updateCommitment(_ commitmentID: String, _ change: CommitmentChange, state: State) {
        changeWork(state, failure: "That work changed. Showing the latest.") { runtime, businessID in
            _ = try await runtime.updateCommitment(businessID, commitmentID, change)
        }
    }
}
