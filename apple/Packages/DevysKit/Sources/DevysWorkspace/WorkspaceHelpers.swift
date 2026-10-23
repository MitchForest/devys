package import DevysClient
import Foundation

/// Pure helpers for the workspace feature; nothing here sends actions or runs effects.
extension Workspace {
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
        /// QA only, for screenshots: DEVYS_PLACE=direct:<id>|project:<id>|thread:<id> opens there
        /// at launch (or `palette` opens ⌘K); DEVYS_LAYER=artifact:<id>|file:<path>
        /// stacks a layer; DEVYS_SIDEBAR=hidden hides the sidebar;
        /// DEVYS_SETTINGS=<section> opens Settings.
        static func applyQAPlace(to state: inout State) {
            let environment = ProcessInfo.processInfo.environment
            func parts(_ name: String) -> (String, String)? {
                guard let raw = environment[name], let colon = raw.firstIndex(of: ":") else { return nil }
                return (String(raw[..<colon]), String(raw[raw.index(after: colon)...]))
            }
            if environment["DEVYS_PLACE"] == "palette" { state.isPaletteOpen = true }
            switch parts("DEVYS_PLACE") {
            case ("direct", let id)?: state.place = .direct(id)
            case ("project", let id)?: state.place = .project(id)
            case ("thread", let id)?: state.place = .thread(id)
            default: break
            }
            switch parts("DEVYS_LAYER") {
            case ("artifact", let id)?: state.layers = [OpenLayer(.artifact(id))]
            case ("file", let path)?: state.layers = [OpenLayer(.file(path))]
            default: break
            }
            if environment["DEVYS_SIDEBAR"] == "hidden" { state.isSidebarVisible = false }
            // DEVYS_SETTINGS=<section> opens Settings there, as the Mac's Settings window does.
            if let section = PreferencesSection.allCases.first(where: { $0.rawValue.lowercased() == environment["DEVYS_SETTINGS"] }) {
                openSettings(at: section, state: &state)
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
    package static func workItemStateSet(_ id: String, _ state: WorkItemState) -> Self {
        Self(.workItemStateSet(workItemID: id, state))
    }
    package static func takeoverToggled(_ id: String) -> Self { Self(.takeoverToggled(workItemID: id)) }
    package static func signTapped(_ id: String) -> Self { Self(.asking(.signTapped(decisionID: id))) }
    package static var signConfirmed: Self { Self(.asking(.signConfirmed)) }
    package static func signFinished(_ error: String?) -> Self { Self(.asking(.signFinished(error))) }
    package static var signDismissed: Self { Self(.asking(.signDismissed)) }
    package static func takeOverTapped(_ workItemID: String) -> Self { Self(.asking(.takeOverTapped(workItemID: workItemID))) }
    package static func secretTapped(_ decisionID: String) -> Self { Self(.asking(.secretTapped(decisionID: decisionID))) }
    package static func fileChosen(_ decisionID: String, _ file: ChosenFile) -> Self { Self(.asking(.fileChosen(decisionID: decisionID, file: file))) }
    package static func secretSubmitted(_ secret: NewSecret) -> Self { Self(.asking(.secretSubmitted(secret))) }
    package static func secretFinished(_ error: String?) -> Self { Self(.asking(.secretFinished(error))) }
    package static var secretDismissed: Self { Self(.asking(.secretDismissed)) }
    package static func newWorkItemTapped(owner: String? = nil, project: String? = nil) -> Self { Self(.workItem(.newWorkItemTapped(ownerID: owner, projectID: project))) }
    package static func workItemEdited(_ draft: WorkItemDraft) -> Self { Self(.workItem(.edited(draft))) }
    package static var workItemConfirmed: Self { Self(.workItem(.confirmed)) }
    package static var workItemCancelled: Self { Self(.workItem(.cancelled)) }
    package static func startTapped(_ id: String) -> Self { Self(.workItem(.startTapped(workItemID: id))) }
    package static func reassigned(_ id: String, to owner: String) -> Self { Self(.workItem(.reassigned(workItemID: id, ownerID: owner))) }
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
    package static func answerPicked(_ key: ConversationKey, _ messageID: String, _ answer: String) -> Self {
        Self(.conversation(.answerPicked(key, messageID: messageID, answer: answer)))
    }
    package static func answersDone(_ key: ConversationKey, _ messageID: String) -> Self { Self(.conversation(.answersDone(key, messageID: messageID))) }
    package static func somethingElseTapped(_ key: ConversationKey) -> Self { Self(.conversation(.somethingElseTapped(key))) }
    package static func uploadChosen(_ key: ConversationKey, _ file: ChosenFile) -> Self { Self(.conversation(.uploadChosen(key, file))) }
    package static func attachmentSet(_ key: ConversationKey, _ ref: Ref?) -> Self { Self(.conversation(.attachmentSet(key, ref))) }
    package static func sidebarMarked(_ key: ConversationKey, _ mark: SidebarMark) -> Self { Self(.sidebar(.marked(key, mark))) }
    package static func connectAppsToggled(_ open: Bool) -> Self { Self(.sidebar(.connectAppsToggled(open))) }
    package static var listedAppsRequested: Self { Self(.sidebar(.listedRequested)) }
    package static func employeeRenamed(_ id: String, _ name: String) -> Self { Self(.team(.renamed(employeeID: id, name: name))) }
    package static func followToggled(_ workItemID: String) -> Self { Self(.conversation(.followToggled(workItemID: workItemID))) }
    package static func retryTapped(_ key: ConversationKey, _ clientID: String) -> Self { Self(.conversation(.retryTapped(key, clientID: clientID))) }
    package static func replyTapped(_ key: ConversationKey, _ messageID: String) -> Self { Self(.conversation(.replyTapped(key, messageID: messageID))) }
    package static func replyCancelled(_ key: ConversationKey) -> Self { Self(.conversation(.replyCancelled(key))) }
    package static func reactionTapped(_ key: ConversationKey, _ messageID: String, _ emoji: String) -> Self {
        Self(.conversation(.reactionTapped(key, messageID: messageID, emoji: emoji)))
    }
    package static func loadOlderTapped(_ key: ConversationKey) -> Self { Self(.conversation(.loadOlderTapped(key))) }
    package static func conversationErrorDismissed(_ key: ConversationKey) -> Self { Self(.conversation(.errorDismissed(key))) }
    package static func placeSelected(_ place: Place) -> Self { Self(.place(.selected(place))) }
    package static func message(_ employeeID: String) -> Self { placeSelected(.direct(employeeID)) }
    package static func threadOpened(_ id: String) -> Self { Self(.place(.threadOpened(id))) }
    package static var backTapped: Self { Self(.place(.backTapped)) }
    package static func layerOpened(_ layer: Layer) -> Self { Self(.place(.layerOpened(layer))) }
    package static func layerReplaced(_ layer: Layer) -> Self { Self(.place(.layerReplaced(layer))) }
    package static var layerPopped: Self { Self(.place(.layerPopped)) }
    package static var layersClosed: Self { Self(.place(.layersClosed)) }
    package static var wideToggled: Self { Self(.place(.wideToggled)) }
    package static func narrowChanged(_ isNarrow: Bool) -> Self { Self(.place(.narrowChanged(isNarrow))) }
    package static func referencingSet(_ isOn: Bool) -> Self { Self(.place(.referencingSet(isOn))) }
    package static func askTapped(_ quote: String) -> Self { Self(.place(.askTapped(quote))) }
    package static func startThreadTapped(_ messageID: String) -> Self { Self(.place(.startThreadTapped(messageID: messageID))) }
    package static func routinePauseTapped(_ id: String) -> Self { Self(.routine(.pauseTapped(routineID: id))) }
    package static func routineResumeTapped(_ id: String) -> Self { Self(.routine(.resumeTapped(routineID: id))) }
    package static var newProjectTapped: Self { Self(.project(.newTapped)) }
    package static var newProjectDismissed: Self { Self(.project(.sheetDismissed)) }
    package static func projectCreateTapped(_ project: ProjectChange) -> Self { Self(.project(.createTapped(project))) }
    package static func projectItemAdded(_ projectID: String, _ ref: Ref) -> Self { Self(.project(.itemAdded(projectID: projectID, ref: ref))) }
    package static func projectItemRemoved(_ projectID: String, _ itemID: String) -> Self {
        Self(.project(.itemRemoved(projectID: projectID, itemID: itemID)))
    }
    package static var sidebarToggled: Self { Self(.sidebarToggled) }
    package static func paletteToggled(_ open: Bool) -> Self { Self(.paletteToggled(open)) }
    package static var refreshTapped: Self { Self(.refreshTapped) }
    package static func activeChanged(_ isActive: Bool) -> Self { Self(.activeChanged(isActive)) }
    /// ⌘.: the employee of the conversation in view.
    package static var stopTapped: Self { Self(.stopTapped(employeeID: nil)) }
    package static func stopTapped(_ employeeID: String) -> Self { Self(.stopTapped(employeeID: employeeID)) }
    package static var noticeDismissed: Self { Self(.noticeDismissed) }
    package static var signOutTapped: Self { Self(.signOutTapped) }
    package static func preferencesToggled(_ open: Bool) -> Self { Self(.preferencesToggled(open)) }
    package static func settingsOpened(_ section: PreferencesSection) -> Self { Self(.settingsOpened(section)) }
    package static var micTapped: Self { Self(.micTapped) }
    package static var conversationToggled: Self { Self(.conversationToggled) }
    package static var stopSpeakingTapped: Self { Self(.stopSpeakingTapped) }
    package static var voiceErrorDismissed: Self { Self(.voiceErrorDismissed) }
}
