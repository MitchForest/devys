import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation

// MARK: - Work and decisions

extension Workspace {
    /// Work, decisions, spaces and their files.
    func reduceWork(_ intent: Intent, state: inout State) {
        switch intent {
        case .workLoaded(let businessID, let work, let decisions, let spaces):
            guard businessID == state.businessID else { return }
            state.work = .loaded(work)
            state.decisions = .loaded(decisions)
            state.spaces = .loaded(spaces)
        case .decisionAnswered(let decisionID, let approve):
            answer(decisionID, approve: approve, state: &state)
        case .commitmentStateSet(let commitmentID, let target):
            setState(commitmentID, target, state: state)
        case .takeoverToggled(let commitmentID):
            toggleTakeover(commitmentID, state: state)
        case .spaceCreateTapped(let space):
            createSpace(space, state: state)
        case .spaceLeadChanged(let spaceID, let leadID):
            changeWork(state, failure: "The lead didn't change. Try again.") { runtime, businessID in
                try await runtime.updateSpace(businessID, spaceID, SpaceChange(lead: leadID))
            }
        case .connectionsRequested:
            loadGoogle(state)
        case .googleLoaded(let connection):
            state.google = connection
        case .spaceItemAdded(let spaceID, let kind, let ref):
            changeWork(state, failure: "That couldn't be added to the space.") { runtime, businessID in
                try await runtime.addToSpace(businessID, spaceID, kind, ref)
            }
        case .spaceItemRemoved(let spaceID, let itemID):
            changeWork(state, failure: "That couldn't be removed from the space.") { runtime, businessID in
                try await runtime.removeFromSpace(businessID, spaceID, itemID)
            }
        case .artifactOpened(let artifactID):
            openArtifact(artifactID, state: &state)
        case .artifactTextLoaded(let artifactID, let text):
            state.artifactTexts[artifactID] = text
        default:
            break
        }
    }

    func loadWork(_ state: State) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            guard let work = try? await runtime.work(businessID),
                  let decisions = try? await runtime.decisions(businessID),
                  let spaces = try? await runtime.spaces(businessID)
            else { return }
            try store.send(Action(.workLoaded(businessID: businessID, work, decisions, spaces)))
        }
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

    /// A space has a name, an optional purpose and a lead (the Head of Operations unless chosen).
    func createSpace(_ space: NewSpace, state: State) {
        let name = space.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let purpose = space.purpose?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let request = NewSpace(name: String(name.prefix(80)), purpose: purpose.isEmpty ? nil : String(purpose.prefix(500)), lead: space.lead)
        changeWork(state, failure: "The space couldn't be created.") { runtime, businessID in
            try await runtime.createSpace(businessID, request)
        }
    }

    /// Google Drive is the one real connection today.
    func loadGoogle(_ state: State) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.googleLoaded(.loaded(try await runtime.googleConnection(businessID)))))
            } catch let error as DevysHTTPError {
                try store.send(Action(.googleLoaded(.failed(Self.message(for: error)))))
            }
        }
    }

    /// Loads a Markdown file's text once, to show it inline.
    func openArtifact(_ artifactID: String, state: inout State) {
        guard state.artifactTexts[artifactID] == nil else { return }
        state.artifactTexts[artifactID] = .loading
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            do {
                let text = try await runtime.artifactText(businessID, artifactID)
                try store.send(Action(.artifactTextLoaded(artifactID: artifactID, .loaded(text))))
            } catch {
                try store.send(Action(.artifactTextLoaded(artifactID: artifactID, .failed("This file couldn't be opened."))))
            }
        }
    }

    /// Applies one change to work, a decision or a space, then shows the server's records again.
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
        guard let work = try? await runtime.work(businessID),
              let decisions = try? await runtime.decisions(businessID),
              let spaces = try? await runtime.spaces(businessID)
        else { return }
        try store.send(Action(.workLoaded(businessID: businessID, work, decisions, spaces)))
    }
}
