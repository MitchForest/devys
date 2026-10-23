import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - Places, the right panel and its layers

package enum PlaceIntent {
    /// From the sidebar or ⌘K: the layers close and Back starts over.
    case selected(Place)
    /// Moves into a work item's thread; Back returns to where the owner was.
    case threadOpened(String)
    case backTapped
    /// Stacks a layer over the right panel; opening what is already on top does nothing.
    case layerOpened(Layer)
    /// Replaces the top layer, as a page's earlier version does.
    case layerReplaced(Layer)
    /// ‹ and Esc: back one layer.
    case layerPopped
    /// ×: back to the permanent view.
    case layersClosed
    /// Shows or hides the right panel for this kind of place, remembered across visits.
    case panelToggled
    case wideToggled
    /// The window became too narrow for the panel beside the conversation, or wide enough again.
    case narrowChanged(Bool)
    /// The reference chip's ×: what's on screen doesn't go with the next message.
    case referencingSet(Bool)
    /// Quotes a selection from a layer into the draft: the owner edits by asking.
    case askTapped(String)
    /// Starts a thread on a message in the conversation on screen.
    case startThreadTapped(messageID: String)
    case threadCreated(WorkItem)
}

extension Workspace.State {
    /// The conversation the place shows; Home waits for the Chief of Staff to load.
    package var mainKey: ConversationKey? { place.conversation(chiefOfStaff: chiefOfStaff?.id) }

    /// Whether the place has a permanent view: a desk (Home's is the Chief of Staff's) or a
    /// project's overview. A thread's work is its card in the conversation.
    package var hasPermanent: Bool {
        place.kind == .direct || place.kind == .project || (place.kind == .home && chiefOfStaff != nil)
    }

    package func panelPreferred(_ kind: Place.Kind) -> Bool { panels[kind] ?? kind.panelByDefault }

    /// A layer always shows the panel; otherwise, when it has something, the place's remembered
    /// choice, or while narrow only what the owner asked for.
    package var isPanelOpen: Bool {
        !layers.isEmpty || (hasPermanent && (isNarrow ? isOverlayOpen : panelPreferred(place.kind)))
    }

    /// Widening applies only while a layer is open.
    package var isWideShown: Bool { isWide && !layers.isEmpty }

    package var topLayer: Layer? { layers.last?.layer }

    package func artifactName(_ id: String) -> String {
        artifacts.first { $0.id == id }.map { $0.filename.replacingOccurrences(of: ".html", with: "") } ?? "Page"
    }

    /// What a layer is, in words, for its header and the reference sent with a message.
    package func reference(for layer: Layer) -> LayerReference {
        let title = switch layer {
        case .artifact(let id, _): artifactName(id)
        case .file(let path): (path as NSString).lastPathComponent
        case .app(let id): appTitle(id)
        case .session: "Coding session"
        case .browser: "Browser"
        case .routine(let id): routine(id)?.title ?? "Routine"
        case .remoteApp(let id): appTitle(id)
        }
        return LayerReference(title: title, ref: layer.ref)
    }

    /// The open layer, sent with the next message unless the owner removed it. An app's
    /// records are a list, not a thing to talk about.
    package var reference: LayerReference? {
        guard isReferencing, let top = topLayer else { return nil }
        if case .app = top { return nil }
        return reference(for: top)
    }

    func appTitle(_ id: String) -> String {
        apps.value?.first { $0.id == id }?.name ?? id.prefix(1).uppercased() + id.dropFirst()
    }

    /// The project a new thread belongs to: the channel's, or the open thread's.
    var currentProjectID: String? {
        switch place {
        case .project(let id): id
        case .thread(let id): work.value?.first { $0.id == id }?.projectID
        case .home, .direct: nil
        }
    }
}

extension Workspace {
    static func panels(from saved: [String: Bool]) -> [Place.Kind: Bool] {
        Dictionary(uniqueKeysWithValues: Place.Kind.allCases.map { ($0, saved[$0.rawValue] ?? $0.panelByDefault) })
    }

    func reducePlace(_ intent: PlaceIntent, state: inout State) {
        switch intent {
        case .selected(let place):
            state.isOverlayOpen = false
            state.history = []
            state.layers = []
            state.isWide = false
            go(to: place, state: &state)
        case .threadOpened(let id):
            guard state.place != .thread(id) else { return }
            state.history.append(state.place)
            state.layers = []
            go(to: .thread(id), state: &state)
        case .backTapped:
            guard let previous = state.history.popLast() else { return }
            state.layers = []
            go(to: previous, state: &state)
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
        case .panelToggled:
            togglePanel(&state)
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
        case .startThreadTapped(let messageID):
            startThread(on: messageID, state: &state)
        case .threadCreated(let item):
            reducePlace(.threadOpened(item.id), state: &state)
        }
    }

    func go(to place: Place, state: inout State) {
        // The Chief of Staff's direct chat is Home.
        state.place = place == .direct(state.chiefOfStaff?.id ?? "") ? .home : place
        openConversation(&state)
    }

    func togglePanel(_ state: inout State) {
        if !state.layers.isEmpty {
            state.layers = []
            state.isWide = false
            return
        }
        if state.isNarrow {
            state.isOverlayOpen.toggle()
            return
        }
        let kind = state.place.kind
        state.panels[kind] = !state.panelPreferred(kind)
        panelsClient.save(Dictionary(uniqueKeysWithValues: state.panels.map { ($0.key.rawValue, $0.value) }))
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
    }

    /// A thread on a message is a work item owned by whoever it addressed (its author, else who
    /// it mentions, else who answers here), in the project it was said in, titled from it.
    func startThread(on messageID: String, state: inout State) {
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
                try store.send(Action(.stopFinished("That thread couldn't be started.")))
                return
            }
            try await reloadWork(runtime, businessID)
            try store.send(Action(.place(.threadCreated(created))))
        }
    }
}
