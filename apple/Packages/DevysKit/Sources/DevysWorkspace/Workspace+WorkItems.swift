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

/// A work item's plan being edited on its work card, after the owner took it over: what's next,
/// what it waits on and the day it's due, saved as one change at the revision on screen.
package struct WorkPlanDraft: Equatable {
    package let workItemID: String
    package var nextAction: String
    package var waiting: String
    package var hasDue: Bool
    /// The day it's due; saved as the end of that day.
    package var due: Date
    package var isSaving = false
    package var error: String?

    package init(_ item: WorkItem) {
        workItemID = item.id
        nextAction = item.nextAction
        waiting = item.waitCondition ?? ""
        let due = item.dueAt.flatMap(ServerDate.parse)
        hasDue = due != nil
        self.due = due ?? Date.now.addingTimeInterval(86_400)
    }

    /// Only what differs from the item as it is now, at its revision; nil when nothing changed.
    package func change(from item: WorkItem) -> WorkItemChange? {
        var change = WorkItemChange(expectedRevision: item.revision)
        let next = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        if next != item.nextAction { change.nextAction = String(next.prefix(1000)) }
        let waiting = waiting.trimmingCharacters(in: .whitespacesAndNewlines)
        if waiting != (item.waitCondition ?? "") { change.waitCondition = waiting.isEmpty ? .clear : .set(String(waiting.prefix(1000))) }
        let saved = item.dueAt.flatMap(ServerDate.parse)
        if !hasDue, saved != nil {
            change.dueAt = .clear
        } else if hasDue, saved.map({ !Calendar.current.isDate($0, inSameDayAs: due) }) ?? true {
            change.dueAt = .set(ServerDate.format(Self.endOfDay(due)))
        }
        return change == WorkItemChange(expectedRevision: item.revision) ? nil : change
    }

    /// 23:59 on that day in the owner's time zone, as the web saves a due date.
    static func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
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
    /// Edit opens the plan of work the owner has taken over; Cancel closes it unsaved.
    case planEditTapped(workItemID: String)
    case planEdited(WorkPlanDraft)
    case planSaveTapped
    case planSaved
    /// The draft stays to save again; the latest item is on screen.
    case planSaveFailed
    case planEditCancelled
    /// Hands the work to another employee, ready to start.
    case reassigned(workItemID: String, ownerID: String)
}

extension Workspace {
    func reduceWorkItem(_ intent: WorkItemIntent, state: inout State) {
        switch intent {
        case .newWorkItemTapped(let ownerID, let projectID):
            guard let owner = ownerID ?? state.chiefOfStaff?.id else { return }
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
        case .planEditTapped(let workItemID):
            guard let item = state.work.value?.first(where: { $0.id == workItemID }), state.isHandEditable(item) else { return }
            state.workPlan = WorkPlanDraft(item)
        case .planEdited(let draft):
            guard state.workPlan?.workItemID == draft.workItemID else { return }
            state.workPlan = draft
        case .planSaveTapped:
            savePlan(state: &state)
        case .planSaved, .planEditCancelled:
            state.workPlan = nil
        case .planSaveFailed:
            state.workPlan?.isSaving = false
            state.workPlan?.error = "That wasn't saved. If it changed meanwhile, the latest is shown; save again to apply."
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

    /// Saves the plan as one change against the item as it is now; with nothing changed, closes.
    func savePlan(state: inout State) {
        guard var draft = state.workPlan, !draft.isSaving, !state.businessID.isEmpty,
              let item = state.work.value?.first(where: { $0.id == draft.workItemID }), state.isHandEditable(item) else { return }
        guard let change = draft.change(from: item) else {
            state.workPlan = nil
            return
        }
        draft.isSaving = true
        draft.error = nil
        state.workPlan = draft
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            let saved: Bool
            do {
                _ = try await runtime.updateWorkItem(businessID, item.id, change)
                saved = true
            } catch {
                saved = false
            }
            // The latest loads either way, so a failed save is retried against it.
            try await reloadWork(runtime, businessID)
            try store.send(Action(.workItem(saved ? .planSaved : .planSaveFailed)))
        }
    }

    func updateWorkItem(_ workItemID: String, _ change: WorkItemChange, state: State) {
        changeWork(state, failure: "That work changed. Showing the latest.") { runtime, businessID in
            _ = try await runtime.updateWorkItem(businessID, workItemID, change)
        }
    }
}
