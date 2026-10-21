import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

// MARK: - Creating and changing work

/// The work item being written in the New work item sheet.
package struct WorkItemDraft: Equatable {
    package var title = ""
    package var ownerID: String
    package var objective = ""
    package var hasDue = false
    package var due: Date
    /// Created from a project, the work item belongs to it.
    package var projectID: String?
    package var isSubmitting = false
    package var error: String?

    package init(ownerID: String, due: Date, projectID: String? = nil) {
        self.ownerID = ownerID
        self.due = due
        self.projectID = projectID
    }

    package var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ownerID.isEmpty && !isSubmitting
    }

    package var workItem: NewWorkItem {
        let objective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewWorkItem(
            title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
            owner: ownerID,
            objective: objective.isEmpty ? nil : String(objective.prefix(4000)),
            dueAt: hasDue ? ServerDate.format(due) : nil,
            projectID: projectID
        )
    }
}

package enum WorkItemIntent {
    /// From New (no presets), an employee's desk (its owner) or a project's overview (its project).
    case newWorkItemTapped(ownerID: String?, projectID: String?)
    case edited(WorkItemDraft)
    case confirmed
    case created(WorkItem)
    case failed(String)
    case cancelled
    /// Any field change on a work item's page, at the revision on screen.
    case changed(workItemID: String, WorkItemChange)
    /// Hands the work to another employee, ready to start.
    case reassigned(workItemID: String, ownerID: String)
}

extension Workspace {
    func reduceWorkItem(_ intent: WorkItemIntent, state: inout State) {
        switch intent {
        case .newWorkItemTapped(let ownerID, let projectID):
            guard let owner = ownerID ?? state.operations?.id else { return }
            state.newWorkItem = WorkItemDraft(ownerID: owner, due: Date.now.addingTimeInterval(86_400), projectID: projectID)
        case .edited(let draft):
            guard state.newWorkItem != nil else { return }
            state.newWorkItem = draft
        case .confirmed:
            submitWorkItem(state: &state)
        case .created(let item):
            // A work item opens its thread once saved.
            state.newWorkItem = nil
            reducePlace(.threadOpened(item.id), state: &state)
        case .failed(let message):
            state.newWorkItem?.isSubmitting = false
            state.newWorkItem?.error = message
        case .cancelled:
            state.newWorkItem = nil
        case .changed(let workItemID, let change):
            updateWorkItem(workItemID, change, state: state)
        case .reassigned(let workItemID, let ownerID):
            guard let item = state.work.value?.first(where: { $0.id == workItemID }), item.ownerEmployeeID != ownerID else { return }
            updateWorkItem(workItemID, .reassign(item, to: ownerID), state: state)
        }
    }

    func submitWorkItem(state: inout State) {
        guard var draft = state.newWorkItem, draft.canCreate, !state.businessID.isEmpty else { return }
        draft.isSubmitting = true
        draft.error = nil
        state.newWorkItem = draft
        let newItem = draft.workItem
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            let created: WorkItem
            do {
                created = try await runtime.createWorkItem(businessID, newItem)
            } catch {
                try store.send(Action(.workItem(.failed("The work item couldn't be saved. Try again."))))
                return
            }
            try await reloadWork(runtime, businessID)
            try store.send(Action(.workItem(.created(created))))
        }
    }

    func updateWorkItem(_ workItemID: String, _ change: WorkItemChange, state: State) {
        changeWork(state, failure: "That work changed. Showing the latest.") { runtime, businessID in
            _ = try await runtime.updateWorkItem(businessID, workItemID, change)
        }
    }
}
