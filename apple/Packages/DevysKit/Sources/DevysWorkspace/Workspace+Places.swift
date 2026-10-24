import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - Places, the right panel and its layers

package enum PlaceIntent {
    /// From the sidebar or ⌘K: the layers close.
    case selected(Place)
    /// Opens a work item beside the conversation on screen, whichever it is: its own stack.
    case workOpened(String)
    /// Opens a work item's live browser over the work, so closing it returns to the work.
    case browserOpened(workID: String)
    /// Stacks a layer over the right panel; opening what is already on top does nothing.
    case layerOpened(Layer)
    /// Replaces the top layer, as a page's earlier version does.
    case layerReplaced(Layer)
    /// ‹ and Esc: back one layer.
    case layerPopped
    /// ×: back to the permanent view.
    case layersClosed
    case wideToggled
    /// The window became too narrow for the panel beside the conversation, or wide enough again.
    case narrowChanged(Bool)
    /// The reference chip's ×: what's on screen doesn't go with the next message.
    case referencingSet(Bool)
    /// Quotes a selection from a layer into the draft: the owner edits by asking.
    case askTapped(String)
    /// Makes a message in the conversation on screen into work.
    case makeWorkTapped(messageID: String)
    case workCreated(WorkItem)
}

extension Workspace.State {
    /// The conversation the place shows; Home waits for the Chief of Staff to load.
    package var mainKey: ConversationKey? { place.conversation(chiefOfStaff: chiefOfStaff?.id) }

    /// The right panel opens only for a layer; a desk or a project's details open from the header.
    package var isPanelOpen: Bool { !layers.isEmpty }

    /// Widening applies only while a layer is open.
    package var isWideShown: Bool { isWide && !layers.isEmpty }

    package var topLayer: Layer? { layers.last?.layer }

    package func artifactName(_ id: String) -> String {
        artifacts.first { $0.id == id }.map { $0.filename.replacingOccurrences(of: ".html", with: "") } ?? "Page"
    }

    /// What a layer is, in words, for its header and the reference sent with a message.
    package func reference(for layer: Layer) -> LayerReference {
        let title = switch layer {
        case .work(let id): work.value?.first { $0.id == id }?.title ?? "Work"
        case .artifact(let id, _): artifactName(id)
        case .file(let path): (path as NSString).lastPathComponent
        case .session: "Coding session"
        case .browser: "Browser"
        case .routine(let id): routine(id)?.title ?? "Routine"
        case .remoteApp(let id): appTitle(id)
        }
        return LayerReference(title: title, ref: layer.ref)
    }

    /// The open layer, sent with the next message unless the owner removed it.
    package var reference: LayerReference? {
        guard isReferencing, let top = topLayer else { return nil }
        return reference(for: top)
    }

    func appTitle(_ id: String) -> String {
        apps.value?.first { $0.id == id }?.name ?? id.prefix(1).uppercased() + id.dropFirst()
    }

    /// The project new work made from a message belongs to: the channel's.
    var currentProjectID: String? {
        if case .project(let id) = place { id } else { nil }
    }

    /// The work item whose layer is in the panel's stack, nearest the top: what a browser, file or
    /// session over it serves, and whose conversation is open beside the main one.
    package var workInPanel: String? {
        for open in layers.reversed() {
            switch open.layer {
            case .work(let id), .browser(let id): return id
            case .session(let id, _): return id
            default: continue
            }
        }
        return nil
    }
}

extension Workspace {
    func reducePlace(_ intent: PlaceIntent, state: inout State) {
        switch intent {
        case .selected(let place):
            state.layers = []
            state.isWide = false
            go(to: place, state: &state)
        case .workOpened(let id), .layerOpened(.work(let id)):
            state.isReferencing = true
            if state.topLayer != .work(id) { state.layers = [OpenLayer(.work(id))] }
        case .browserOpened(let workID):
            state.isReferencing = true
            state.layers = [OpenLayer(.work(workID)), OpenLayer(.browser(workID: workID))]
        case .layerOpened(let layer):
            state.isReferencing = true
            if state.topLayer != layer { state.layers.append(OpenLayer(layer)) }
        case .layerReplaced(let layer):
            if !state.layers.isEmpty { state.layers.removeLast() }
            state.layers.append(OpenLayer(layer))
        case .layerPopped:
            if !state.layers.isEmpty { state.layers.removeLast() }
        case .layersClosed:
            state.layers = []
            state.isWide = false
        case .wideToggled:
            state.isWide.toggle()
        case .narrowChanged(let isNarrow):
            state.isNarrow = isNarrow
        case .referencingSet(let isOn):
            state.isReferencing = isOn
        case .askTapped(let quote):
            guard let key = state.main?.key else { return }
            let lines = quote.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false).prefix(12)
            update(key, &state) { $0.draft = lines.map { "> \($0)" }.joined(separator: "\n") + "\n\n" + $0.draft }
        case .makeWorkTapped(let messageID):
            makeWork(of: messageID, state: &state)
        case .workCreated(let item):
            reducePlace(.workOpened(item.id), state: &state)
        }
        syncAside(&state)
    }

    /// The work open beside the conversation keeps its own conversation open while it is there.
    func syncAside(_ state: inout State) {
        let key = state.workInPanel.map(ConversationKey.work)
        guard key != state.aside?.key else { return }
        state.aside = key.map(OpenConversation.init)
        if let key { loadPage(key, state: state) }
    }

    func go(to place: Place, state: inout State) {
        // The Chief of Staff's direct chat is Home.
        state.place = place == .direct(state.chiefOfStaff?.id ?? "") ? .home : place
        openConversation(&state)
    }

    /// A page published in the conversation on screen opens on its own unless the owner opened a
    /// layer themselves; a new version of the open page replaces it in place and says who.
    func pageArrived(_ message: ConversationMessage, state: inout State) {
        guard let id = message.ref?.page else { return }
        let author = message.employeeID.flatMap { id in state.snapshot.employees.first { $0.id == id }?.name }
        let artifacts = state.artifacts
        func name(_ artifactID: String) -> String { artifacts.first { $0.id == artifactID }?.filename ?? message.text }
        state.isReferencing = true
        if let top = state.layers.last, case .artifact(let open, _) = top.layer, name(open) == name(id) {
            state.layers[state.layers.count - 1].layer = .artifact(id, updatedBy: author)
        } else if state.layers.last?.auto ?? true {
            state.layers = [OpenLayer(.artifact(id), auto: true)]
        }
        syncAside(&state)
    }

    /// Work made from a message is owned by whoever it addressed (its author, else who it
    /// mentions, else who answers here), in the project it was said in, titled from it.
    func makeWork(of messageID: String, state: inout State) {
        guard let open = state.main, let message = open.message(messageID), !state.businessID.isEmpty else { return }
        let owner = message.employeeID ?? message.mentions.first ?? state.recipients(in: open.key).first ?? state.chiefOfStaff?.id
        guard let owner else { return }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newItem = NewWorkItem(
            title: String((text.split(separator: "\n").first.map(String.init) ?? text).prefix(80)),
            owner: owner,
            objective: String(text.prefix(4000)),
            projectID: state.currentProjectID
        )
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            let created: WorkItem
            do {
                created = try await runtime.createWorkItem(businessID, newItem)
            } catch {
                try store.send(Action(.stopFinished("That work couldn't be started.")))
                return
            }
            try await reloadWork(runtime, businessID)
            try store.send(Action(.place(.workCreated(created))))
        }
    }
}
