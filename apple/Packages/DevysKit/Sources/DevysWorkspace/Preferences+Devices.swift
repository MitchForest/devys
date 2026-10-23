import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

// MARK: - New businesses, business details and devices

/// A business being set up: its name, brief and starting team.
package struct NewBusinessDraft: Equatable {
    package var name = ""
    package var brief = ""
    /// Starting-team templates hired alongside the Chief of Staff; all on by default.
    package var team = Set(RoleTemplate.startingTeam)
    package var isSubmitting = false
    package var error: String?

    package init() {}

    package var canCreate: Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 80 && !isSubmitting
    }

    package var request: NewBusiness {
        NewBusiness(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brief: String(brief.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)),
            team: RoleTemplate.startingTeam.filter(team.contains)
        )
    }
}

package enum BusinessIntent {
    case newTapped
    case edited(NewBusinessDraft)
    case createTapped
    case created
    case createFailed(String)
    case cancelled
    case saveTapped(id: String, name: String, brief: String)
    case saved(Business)
}

package enum DeviceIntent {
    case requested
    case loaded(Loadable<[Device]>)
    case revokeTapped(String)
    case addTapped
    case connectLinkLoaded(ConnectLink)
    case connectDismissed
    case openInBrowserTapped
    case browserLinkLoaded(URL)
    case browserLinkOpened
    case keysLoaded([DeviceKey])
    /// Lets another device's pending key sign, with this device's signature (Face ID or Touch ID).
    case allowTapped(keyID: String)
}

extension Preferences {
    func reduceBusiness(_ intent: BusinessIntent, state: inout State) {
        switch intent {
        case .newTapped:
            state.newBusiness = NewBusinessDraft()
        case .edited(let draft):
            guard state.newBusiness != nil else { return }
            state.newBusiness = draft
        case .createTapped:
            guard var draft = state.newBusiness, draft.canCreate else { return }
            draft.isSubmitting = true
            draft.error = nil
            state.newBusiness = draft
            let request = draft.request
            let runtime = runtime
            store.addTask {
                do {
                    _ = try await runtime.createBusiness(request)
                } catch {
                    try store.send(Action(.business(.createFailed("The business couldn't be created. Try again."))))
                    return
                }
                try store.send(Action(.business(.created)))
                try await loadDirectory(runtime)
            }
        case .created:
            state.newBusiness = nil
        case .createFailed(let message):
            state.newBusiness?.isSubmitting = false
            state.newBusiness?.error = message
        case .cancelled:
            state.newBusiness = nil
        case .saveTapped(let id, let name, let brief):
            saveBusiness(id, name: name, brief: brief, state: &state)
        case .saved(let business):
            guard let index = state.businesses.firstIndex(where: { $0.id == business.id }) else { return }
            state.businesses[index].name = business.name
            state.businesses[index].brief = business.brief
        }
    }

    /// Sends only what changed; the saved business shows at once.
    func saveBusiness(_ id: String, name: String, brief: String, state: inout State) {
        guard let current = state.businesses.first(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let brief = String(brief.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !name.isEmpty, name.count <= 80 else {
            state.errorText = "A business needs a name of up to 80 characters."
            return
        }
        let newName = name == current.name ? nil : name
        let newBrief = brief == current.brief ? nil : brief
        guard newName != nil || newBrief != nil else { return }
        state.errorText = nil
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.business(.saved(try await runtime.updateBusiness(id, newName, newBrief)))))
            } catch {
                try store.send(Action(.failed("That change didn't save. Try again.")))
            }
        }
    }

    func reduceDevice(_ intent: DeviceIntent, state: inout State) {
        switch intent {
        case .requested:
            loadDevices()
        case .loaded(let devices):
            state.devices = devices
        case .revokeTapped(let id):
            // Signing this device out goes through Sign out, which also forgets the session here.
            guard state.devices.value?.first(where: { $0.id == id })?.current == false else { return }
            if let devices = state.devices.value { state.devices = .loaded(devices.filter { $0.id != id }) }
            let runtime = runtime
            store.addTask {
                do {
                    try await runtime.revokeDevice(id)
                } catch {
                    try store.send(Action(.failed("That device couldn't be signed out. Try again.")))
                }
                try await loadDevices(runtime)
            }
        case .addTapped:
            state.errorText = nil
            let runtime = runtime
            store.addTask {
                do {
                    let hello = try await runtime.hello()
                    try store.send(Action(.device(.connectLinkLoaded(ConnectLink(mac: FoundMac(name: hello.name, server: hello.url))))))
                } catch {
                    try store.send(Action(.failed("Couldn't reach Devys. Try again.")))
                }
            }
        case .connectLinkLoaded(let link):
            state.connectLink = link
        case .connectDismissed:
            state.connectLink = nil
            loadDevices()
        case .openInBrowserTapped:
            let runtime = runtime
            store.addTask {
                do {
                    try store.send(Action(.device(.browserLinkLoaded(try await runtime.signInLink()))))
                } catch {
                    try store.send(Action(.failed("Couldn't open the browser. Try again.")))
                }
            }
        case .browserLinkLoaded(let url):
            state.browserLink = url
        case .browserLinkOpened:
            state.browserLink = nil
        case .keysLoaded(let keys):
            state.keys = keys
        case .allowTapped(let keyID):
            guard let key = state.keys.first(where: { $0.id == keyID && $0.status == .pending }), let person = state.ownerID else { return }
            let signing = signing
            let runtime = runtime
            store.addTask {
                do {
                    try await signing.allow(key, person)
                } catch {
                    try store.send(Action(.failed(Workspace.signingMessage(error))))
                }
                try await loadDevices(runtime)
            }
        }
    }

    func loadDevices() {
        let runtime = runtime
        store.addTask { try await loadDevices(runtime) }
    }

    private func loadDevices(_ runtime: RuntimeClient) async throws {
        do {
            try store.send(Action(.device(.loaded(.loaded(try await runtime.devices())))))
        } catch {
            try store.send(Action(.device(.loaded(.failed("Devices couldn't be loaded.")))))
        }
        if let keys = try? await signing.keys() { try store.send(Action(.device(.keysLoaded(keys)))) }
    }
}
