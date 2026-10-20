package import DevysClient
import Foundation

/// Pure helpers for the workspace feature; nothing here sends actions or runs effects.
extension Workspace {
    /// Panels, tabs and layouts: view state only.
    func reduceLayout(_ intent: Intent, state: inout State) {
        switch intent {
        case .sidebarToggled:
            state.isSidebarVisible.toggle()

        case .inspectorToggled:
            state.isInspectorVisible.toggle()

        case .paletteToggled(let open):
            state.isPaletteOpen = open

        case .spaceTabSelected(let tab):
            state.spaceTab = tab
            if let key = state.main?.key { markRead(key, state: &state) }

        case .employeeTabSelected(let tab):
            state.employeeTab = tab

        case .workLayoutSelected(let layout):
            state.workLayout = layout

        default:
            break
        }
    }

    static func defaultPage(for destination: Destination, snapshot: WorkspaceSnapshot) -> Page {
        switch destination {
        case .home: .today
        case .inbox: .inbox
        case .work: .work(.all)
        case .team: .employee(snapshot.employees.first?.id)
        case .money: .money
        case .apps: .apps(.installed)
        }
    }

    static func message(for error: DevysHTTPError) -> String {
        switch error {
        case .unreachable: "The server isn't reachable."
        case .rejected(let status, _): "The server answered \(status)."
        case .invalidResponse: "The server sent something unexpected."
        case .unauthorized: "Your session ended."
        }
    }

}

extension Workspace {
    #if DEBUG
        /// QA only: DEVYS_PAGE opens a page at launch for screenshots.
        static func applyQAPage(to state: inout State) {
            switch ProcessInfo.processInfo.environment["DEVYS_PAGE"] {
            case "approvals": state.page = .approvals
            case "files": state.page = .files(nil)
            case "space": state.page = state.spaces.value?.first.map { .space($0.id) } ?? .today
            case "team": state.page = .employee(state.snapshot.employees.first?.id)
            case "memory":
                state.page = .employee(state.snapshot.employees.first?.id)
                state.employeeTab = .memory
            case "work": state.page = .work(.all)
            case "board":
                state.page = .work(.all)
                state.workLayout = .board
            case "inbox": state.page = .inbox
            case "money": state.page = .money
            case "connections": state.page = .apps(.connections)
            case "palette": state.isPaletteOpen = true
            case "conversation": state.page = state.operations.map { .direct($0.id) } ?? .today
            default: break
            }
        }
    #endif
}

extension Workspace.Action {
    package static func businessSelected(_ id: String) -> Self { Self(.businessSelected(id)) }
    package static func accessRequested(_ employeeID: String) -> Self { Self(.accessRequested(employeeID: employeeID)) }
    package static func grantTapped(_ employeeID: String, _ capability: String, _ mode: AccessMode) -> Self {
        Self(.grantTapped(employeeID: employeeID, capability: capability, mode: mode))
    }
    package static func revokeTapped(_ employeeID: String, _ grantID: String) -> Self {
        Self(.revokeTapped(employeeID: employeeID, grantID: grantID))
    }
    package static func pauseToggled(_ employeeID: String) -> Self { Self(.pauseToggled(employeeID: employeeID)) }
    package static func modelRequested(_ employeeID: String) -> Self { Self(.model(.requested(employeeID: employeeID))) }
    package static func modelSelected(_ employeeID: String, _ model: String) -> Self {
        Self(.model(.selected(employeeID: employeeID, model: model)))
    }
    package static func decisionAnswered(_ id: String, approve: Bool) -> Self { Self(.decisionAnswered(decisionID: id, approve: approve)) }
    package static func commitmentStateSet(_ id: String, _ state: CommitmentState) -> Self {
        Self(.commitmentStateSet(commitmentID: id, state))
    }
    package static func takeoverToggled(_ id: String) -> Self { Self(.takeoverToggled(commitmentID: id)) }
    package static func newTaskTapped(owner: String? = nil, space: String? = nil) -> Self { Self(.task(.newTaskTapped(ownerID: owner, spaceID: space))) }
    package static func taskEdited(_ draft: TaskDraft) -> Self { Self(.task(.edited(draft))) }
    package static var taskConfirmed: Self { Self(.task(.confirmed)) }
    package static var taskCancelled: Self { Self(.task(.cancelled)) }
    package static func commitmentChanged(_ id: String, _ change: CommitmentChange) -> Self { Self(.task(.changed(commitmentID: id, change))) }
    package static func reassigned(_ id: String, to owner: String) -> Self { Self(.task(.reassigned(commitmentID: id, ownerID: owner))) }
    package static var hireTapped: Self { Self(.team(.hireTapped)) }
    package static func templateChosen(_ id: String) -> Self { Self(.team(.templateChosen(id))) }
    package static func hireEdited(_ draft: HireDraft) -> Self { Self(.team(.hireEdited(draft))) }
    package static var hireConfirmed: Self { Self(.team(.hireConfirmed)) }
    package static var hireCancelled: Self { Self(.team(.hireCancelled)) }
    package static func profileSaved(_ id: String, name: String, responsibilities: String) -> Self {
        Self(.team(.profileSaved(employeeID: id, name: name, responsibilities: responsibilities)))
    }
    package static func retireConfirmed(_ id: String, successor: String) -> Self { Self(.team(.retireConfirmed(employeeID: id, successorID: successor))) }
    package static func draftChanged(_ key: ConversationKey, _ text: String) -> Self { Self(.conversation(.draftChanged(key, text))) }
    package static func mentionPicked(_ key: ConversationKey, _ employeeID: String) -> Self { Self(.conversation(.mentionPicked(key, employeeID: employeeID))) }
    package static func responderPicked(_ key: ConversationKey, _ employeeID: String?) -> Self {
        Self(.conversation(.responderPicked(key, employeeID: employeeID)))
    }
    package static func sendTapped(_ key: ConversationKey) -> Self { Self(.conversation(.sendTapped(key))) }
    package static func retryTapped(_ key: ConversationKey, _ clientID: String) -> Self { Self(.conversation(.retryTapped(key, clientID: clientID))) }
    package static func replyTapped(_ key: ConversationKey, _ messageID: String) -> Self { Self(.conversation(.replyTapped(key, messageID: messageID))) }
    package static func replyCancelled(_ key: ConversationKey) -> Self { Self(.conversation(.replyCancelled(key))) }
    package static func reactionTapped(_ key: ConversationKey, _ messageID: String, _ emoji: String) -> Self {
        Self(.conversation(.reactionTapped(key, messageID: messageID, emoji: emoji)))
    }
    package static func loadOlderTapped(_ key: ConversationKey) -> Self { Self(.conversation(.loadOlderTapped(key))) }
    package static func conversationErrorDismissed(_ key: ConversationKey) -> Self { Self(.conversation(.errorDismissed(key))) }
    package static func workOpened(_ id: String) -> Self { Self(.conversation(.workOpened(id))) }
    package static var workClosed: Self { Self(.conversation(.workClosed)) }
    package static func spaceLeadChanged(_ spaceID: String, _ leadID: String) -> Self { Self(.spaceLeadChanged(spaceID: spaceID, leadID: leadID)) }
    package static var allUsageRequested: Self { Self(.model(.allUsageRequested)) }
    package static var connectionsRequested: Self { Self(.connectionsRequested) }
    package static func destinationSelected(_ destination: Destination) -> Self { Self(.destinationSelected(destination)) }
    package static func pageSelected(_ page: Page) -> Self { Self(.pageSelected(page)) }
    package static var sidebarToggled: Self { Self(.sidebarToggled) }
    package static var inspectorToggled: Self { Self(.inspectorToggled) }
    package static func paletteToggled(_ open: Bool) -> Self { Self(.paletteToggled(open)) }
    package static func spaceTabSelected(_ tab: SpaceTab) -> Self { Self(.spaceTabSelected(tab)) }
    package static func spaceCreateTapped(_ space: NewSpace) -> Self { Self(.spaceCreateTapped(space)) }
    package static func spaceItemAdded(_ spaceID: String, _ kind: SpaceItem.Kind, _ ref: String) -> Self {
        Self(.spaceItemAdded(spaceID: spaceID, kind: kind, ref: ref))
    }
    package static func spaceItemRemoved(_ spaceID: String, _ itemID: String) -> Self {
        Self(.spaceItemRemoved(spaceID: spaceID, itemID: itemID))
    }
    package static func artifactOpened(_ id: String) -> Self { Self(.artifactOpened(artifactID: id)) }
    package static func employeeTabSelected(_ tab: EmployeeTab) -> Self { Self(.employeeTabSelected(tab)) }
    package static func workLayoutSelected(_ layout: WorkLayout) -> Self { Self(.workLayoutSelected(layout)) }
    package static var refreshTapped: Self { Self(.refreshTapped) }
    package static var stopTapped: Self { Self(.stopTapped) }
    package static var noticeDismissed: Self { Self(.noticeDismissed) }
    package static var signOutTapped: Self { Self(.signOutTapped) }
    package static func preferencesToggled(_ open: Bool) -> Self { Self(.preferencesToggled(open)) }
    package static var micTapped: Self { Self(.micTapped) }
    package static var conversationToggled: Self { Self(.conversationToggled) }
    package static var stopSpeakingTapped: Self { Self(.stopSpeakingTapped) }
    package static var voiceErrorDismissed: Self { Self(.voiceErrorDismissed) }
    package static func presenceTapped(_ id: String) -> Self { Self(.presenceTapped(id)) }
}
