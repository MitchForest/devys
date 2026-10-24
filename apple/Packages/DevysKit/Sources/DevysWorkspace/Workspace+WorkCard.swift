package import DevysClient
import Foundation

// MARK: - A work item's one live card: where it stands, in one line

/// The one line of state a work item's card shows, with at most one thing for the owner to do.
package enum WorkCardLine: Equatable {
    /// Its employee is running on it now, doing this (in the owner's words; the plan shows the
    /// step). Stop.
    case working(String)
    /// A plan waiting for the owner's Start.
    case ready
    /// The one request waiting on the owner, with its one action.
    case yourTurn(NeedsYouItem)
    /// The owner has taken it over. Hand back.
    case yours
    case waiting(String)
    case done
    case upNext(String)
    case quiet
}

extension Workspace.State {
    /// The earliest request waiting on the owner for this work item; there is at most one
    /// `askOwner` at a time, and a capability held in ask may wait beside it.
    package func request(for item: WorkItem) -> NeedsYouItem? {
        (home.value?.needsYou ?? [])
            .filter { $0.decision?.workItemID == item.id }
            .min { ($0.decision?.requestedAt ?? "") < ($1.decision?.requestedAt ?? "") }
    }

    /// Requests not bound to a work item (a hire, a routine, an app to connect), each shown once
    /// where it was asked: its project's channel, Home for the Chief of Staff, otherwise the
    /// employee's direct chat.
    package func requests(in key: ConversationKey) -> [NeedsYouItem] {
        (home.value?.needsYou ?? []).filter { item in
            guard let decision = item.decision, decision.workItemID == nil else { return false }
            if let project = item.projectID { return key == .project(project) }
            return key == .direct(decision.employeeID)
        }
    }

    /// Its owner employee's run is for this work item's thread right now.
    package func isWorking(on item: WorkItem) -> Bool {
        guard let run = statuses[item.ownerEmployeeID]?.state.run, !run.stopped else { return false }
        return run.conversation == ConversationKey.work(item.id).rawValue
    }

    package func cardLine(_ item: WorkItem) -> WorkCardLine {
        if item.state == .completed { return .done }
        if isMine(item), item.state.isOpen { return .yours }
        if let request = request(for: item) { return .yourTurn(request) }
        if item.state == .proposed { return .ready }
        if isWorking(on: item) { return .working(statuses[item.ownerEmployeeID]?.state.run?.doing ?? "Working") }
        if item.state == .waiting, let condition = item.waitCondition, !condition.isEmpty { return .waiting(condition) }
        if item.state.isOpen, !item.nextAction.isEmpty { return .upNext(item.nextAction) }
        return .quiet
    }

    /// "Step 3 of 5": the first step not yet done; nil without steps or once all are done.
    package func stepPosition(_ item: WorkItem) -> String? {
        guard let current = item.steps.firstIndex(where: { $0.state != .done }) else { return nil }
        return "Step \(current + 1) of \(item.steps.count)"
    }

    /// The employee of the conversation in view, whom ⌘. stops: Home's Chief of Staff, a direct
    /// chat's employee, a channel's lead, a thread's owner.
    package var employeeInView: String? {
        mainKey.flatMap(defaultResponder(for:))
    }
}

extension DecisionText {
    /// The ask in a few plain words, after "Your turn: ".
    static func ask(_ request: NeedsYouItem) -> String {
        guard let decision = request.decision else { return request.title }
        switch decision.request {
        case .connect: return "Connect \(request.app?.name ?? "an app")"
        case .secret(_, _, let spend): return spend ? "Add your card" : "Add a secret"
        default: return title(decision)
        }
    }
}
