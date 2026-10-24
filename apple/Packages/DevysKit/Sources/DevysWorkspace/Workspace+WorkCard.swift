package import DevysClient
package import Foundation

// MARK: - A work item's one live card: where it stands, in one line

/// Where a work item stands, in one line and one tone.
package struct WorkStatus: Equatable {
    package enum Tone: Equatable { case you, working, done, quiet }
    package let tone: Tone
    package let text: String
}

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

    /// Where a work item stands in one line, for its chip in a conversation and its sidebar row:
    /// what the owner is asked to do, what its employee is doing now, or how far it got.
    package func workStatus(_ item: WorkItem) -> WorkStatus {
        switch cardLine(item) {
        case .working(let doing): WorkStatus(tone: .working, text: "\(doing)…")
        case .ready: WorkStatus(tone: .you, text: "Ready when you are")
        case .yourTurn(let request): WorkStatus(tone: .you, text: "Your turn: \(DecisionText.ask(request))")
        case .yours: WorkStatus(tone: .you, text: "You have it")
        case .waiting(let condition): WorkStatus(tone: .quiet, text: "Waiting on \(condition)")
        case .done: WorkStatus(tone: .done, text: "Done")
        case .upNext, .quiet:
            if item.state == .cancelled {
                WorkStatus(tone: .quiet, text: "Cancelled")
            } else if item.state == .needsDecision {
                WorkStatus(tone: .you, text: "Your turn")
            } else {
                WorkStatus(tone: .quiet, text: stepPosition(item) ?? (item.nextAction.isEmpty ? (item.state == .ready ? "Not started" : "Under way") : item.nextAction))
            }
        }
    }

    /// Whether the signed-in person pinned this work item to the top of Work.
    package func isPinned(work id: String) -> Bool {
        summaries[ConversationKey.work(id).rawValue]?.pinned ?? false
    }

    /// The work in the sidebar: what the owner pinned first, whatever its state, until unpinned;
    /// then everything open, and finished work until the owner has seen how it ended (its last
    /// word unread) for at most a day; it is archived after that, still found with ⌘K. Those
    /// waiting on the owner first, then the ones running, then the rest, newest first.
    package func activeWork(now: Date = .now) -> [WorkItem] {
        let all = work.value ?? []
        let shown = all.filter { item in
            if isPinned(work: item.id) { return false }
            switch item.state {
            case .completed:
                let unread = summaries[ConversationKey.work(item.id).rawValue]?.unread ?? 0
                return unread > 0 && now.timeIntervalSince(ServerDate.parse(item.updatedAt) ?? .distantPast) < 86_400
            case .cancelled: return false
            default: return true
            }
        }
        func rank(_ item: WorkItem) -> Int {
            if request(for: item) != nil || item.state == .proposed || item.state == .needsDecision { return 0 }
            if item.state == .inProgress || item.state == .ready { return 1 }
            return item.state == .completed ? 3 : 2
        }
        return all.filter { isPinned(work: $0.id) } + shown.sorted { (rank($0), $1.updatedAt) < (rank($1), $0.updatedAt) }
    }

    /// "Step 3 of 5": the first step not yet done; nil without steps or once all are done.
    package func stepPosition(_ item: WorkItem) -> String? {
        guard let current = item.steps.firstIndex(where: { $0.state != .done }) else { return nil }
        return "Step \(current + 1) of \(item.steps.count)"
    }

    /// The employee ⌘. stops: the owner of the work open beside the conversation, else the
    /// conversation's own (Home's Chief of Staff, a direct chat's employee, a channel's lead).
    package var employeeInView: String? {
        if let workID = workInPanel { return work.value?.first { $0.id == workID }?.ownerEmployeeID }
        return mainKey.flatMap(defaultResponder(for:))
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
