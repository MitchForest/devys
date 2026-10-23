import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@MainActor
private func settle(_ what: String, until condition: @MainActor () async -> Bool) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(what)")
}

nonisolated private let mini = FoundMac(name: "Sam's Mac mini", server: URL(string: "http://mac-mini:8787")!)
nonisolated private let office = FoundMac(name: "Office iMac", server: URL(string: "http://office:8787")!)

/// The session hub as the sign-in screen sees it: whether this is the Mac running Devys, and how a
/// request to join is answered.
private actor Joining {
    var ownerAttempts = 0
    var asked: [FoundMac] = []
    var remembered: [FoundMac] = []
    /// Owner sign-ins that fail before one answers (the server is starting).
    var ownerFailures = 0
    var isOwnersMac = false
    var outcome = JoinOutcome.allowed
    var unreachable = false

    func configure(owner: Bool = false, failures: Int = 0, outcome: JoinOutcome = .allowed, unreachable: Bool = false) {
        isOwnersMac = owner
        ownerFailures = failures
        self.outcome = outcome
        self.unreachable = unreachable
    }

    func signInAsOwner() throws -> Bool {
        ownerAttempts += 1
        if ownerFailures > 0 {
            ownerFailures -= 1
            throw DevysHTTPError.unreachable("starting")
        }
        return isOwnersMac
    }

    func request(_ mac: FoundMac) throws -> JoinTicket {
        if unreachable { throw DevysHTTPError.unreachable("offline") }
        asked.append(mac)
        return JoinTicket(id: "join-\(asked.count)", mac: mac, match: ["🦊", "🌵"])
    }

    func remember(_ mac: FoundMac) { remembered.append(mac) }
}

@MainActor
@Suite("Signing in")
struct SignInTests {
    /// `answer` gates the answer to a request, so a test can look at the waiting screen first.
    private func makeStore(
        _ joining: Joining,
        last: FoundMac? = nil,
        found: [FoundMac] = [],
        answer: AsyncStream<Void> = AsyncStream { $0.finish() }
    ) -> StoreOf<SignIn> {
        withDependencies {
            $0.sessionClient = SessionClient(
                phases: { AsyncStream { $0.finish() } },
                signInAsOwner: { try await joining.signInAsOwner() },
                requestJoin: { try await joining.request($0) },
                awaitJoin: { _ in
                    for await _ in answer {}
                    return await joining.outcome
                },
                signOut: {}
            )
            $0.discoveryClient = DiscoveryClient(
                macs: { AsyncStream { continuation in
                    for mac in found { continuation.yield(mac) }
                } },
                lastKnown: { last },
                remember: { mac in Task { await joining.remember(mac) } }
            )
            $0.continuousClock = ImmediateClockStandIn()
        } operation: {
            Store(initialState: SignIn.State()) { SignIn() }
        }
    }

    @Test("On the Mac running Devys it signs in as the owner, retrying until the server answers, and never looks further")
    func ownersMac() async {
        let joining = Joining()
        await joining.configure(owner: true, failures: 2)
        let store = makeStore(joining, last: mini, found: [office])
        store.send(.appeared)
        await settle("owner sign-in", until: { await joining.ownerAttempts == 3 })
        for _ in 0..<200 { await Task.yield() }
        #expect(store.phase == .looking)
        #expect(await joining.asked.isEmpty)
    }

    @Test("Elsewhere it looks, shows the last Mac at once, then the one the network finds")
    func discovers() async {
        let joining = Joining()
        let looking = makeStore(joining)
        #expect(looking.phase == .looking)
        let store = makeStore(joining, last: mini, found: [office])
        store.send(.appeared)
        await settle("found", until: { store.phase == .found(office) })
        #expect(store.mac == office)
    }

    @Test("Connect asks to join, shows the two emoji while waiting, and allowed remembers the Mac")
    func connects() async {
        let joining = Joining()
        let (answer, answered) = AsyncStream<Void>.makeStream()
        let store = makeStore(joining, last: mini, answer: answer)
        store.send(.appeared)
        await settle("found", until: { store.phase == .found(mini) })
        store.send(.connectTapped)
        #expect(store.phase == .connecting(mini))
        await settle("waiting", until: {
            if case .waiting(let ticket) = store.phase { return ticket.match == ["🦊", "🌵"] }
            return false
        })
        answered.finish()
        await settle("remembered", until: { await joining.remembered == [mini] })
        #expect(await joining.asked == [mini])
        #expect(store.errorText == nil)
    }

    @Test("Denied or expired, it is back at its button with nothing to read")
    func deniedQuietly() async {
        for outcome in [JoinOutcome.denied, .expired] {
            let joining = Joining()
            await joining.configure(outcome: outcome)
            let store = makeStore(joining, last: mini)
            store.send(.appeared)
            await settle("found", until: { store.phase == .found(mini) })
            store.send(.connectTapped)
            await settle("answered", until: { await joining.asked.count == 1 && store.phase == .found(mini) })
            #expect(store.errorText == nil)
            #expect(await joining.remembered.isEmpty)
        }
    }

    @Test("Unreachable, one short line says so and the button stays")
    func unreachable() async {
        let joining = Joining()
        await joining.configure(unreachable: true)
        let store = makeStore(joining, last: mini)
        store.send(.appeared)
        await settle("found", until: { store.phase == .found(mini) })
        store.send(.connectTapped)
        await settle("failed", until: { store.errorText != nil })
        #expect(store.phase == .found(mini))
        #expect(store.errorText == "Couldn't reach your Mac. Try again.")
    }
}

@MainActor
@Suite("Connect links")
struct ConnectLinkTests {
    @Test("The QR code's link shows its Mac on the button; signed in, it changes nothing")
    func opensOnTheButton() async {
        let (phases, continuation) = AsyncStream<SessionPhase>.makeStream()
        let store = withDependencies {
            $0.sessionClient = SessionClient(phases: { phases }, signOut: {})
            $0.discoveryClient = .none
            $0.runtimeClient = .fixture
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: DevysApp.State()) { DevysApp() }
        }
        let link = ConnectLink(mac: mini).url
        #expect(link.absoluteString == "devys://connect?server=http%3A%2F%2Fmac-mini%3A8787&name=Sam's%20Mac%20mini")
        #expect(ConnectLink(url: link)?.mac == mini)
        #expect(ConnectLink(url: URL(string: "devys://connect?server=ftp%3A%2F%2Fx")!) == nil)
        continuation.yield(.signedOut)
        await settle("signed out", until: { store.route == .signedOut })
        store.send(.linkOpened(link))
        #expect(store.spawn(\.signIn)?.phase == .found(mini))
        continuation.yield(.signedIn(server: mini.server))
        await settle("signed in", until: { store.route == .signedIn })
        store.send(.linkOpened(link))
        #expect(store.linkedMac == nil)
    }
}

private struct BusinessUpdate: Equatable {
    let id: String
    let name: String?
    let brief: String?
}

private actor DeviceServer {
    var devices = [
        Device(id: "aaaaaaaaaaaaaaaa", label: "Mitch's Mac", createdAt: "2026-10-19T15:00:00Z", expiresAt: "2026-10-26T15:00:00Z", current: true),
        Device(id: "bbbbbbbbbbbbbbbb", label: "Mitch's iPad", createdAt: "2026-10-18T15:00:00Z", expiresAt: "2026-10-25T15:00:00Z", current: false)
    ]
    var revoked: [String] = []
    var created: [NewBusiness] = []
    var updates: [BusinessUpdate] = []
    var names: [String] = []

    func revoke(_ id: String) {
        revoked.append(id)
        devices.removeAll { $0.id == id }
    }
    func create(_ business: NewBusiness) -> Business {
        created.append(business)
        return Business(id: "new", name: business.name, brief: business.brief)
    }
    func rename(_ name: String) -> Account {
        names.append(name)
        return Account(person: Person(id: "person-preview", displayName: name), businesses: Account.fixture.businesses)
    }
    func update(_ id: String, _ name: String?, _ brief: String?) -> Business {
        updates.append(BusinessUpdate(id: id, name: name, brief: brief))
        return Business(id: id, name: name ?? "Acme", brief: brief ?? "")
    }
}

@MainActor
@Suite("Settings: devices and businesses")
struct DevicesAndBusinessesTests {
    private func makeStore(_ server: DeviceServer) -> StoreOf<Preferences> {
        withDependencies {
            $0.lookClient = .inert
            $0.profileClient = .inert
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                rename: { await server.rename($0) },
                business: { BusinessDetail.fixture($0) },
                createBusiness: { await server.create($0) },
                updateBusiness: { await server.update($0, $1, $2) },
                devices: { await server.devices },
                revokeDevice: { await server.revoke($0) },
                hello: { Hello(name: "Sam's Mac mini", url: URL(string: "http://mac-mini:8787")!) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] }
            )
        } operation: {
            Store(initialState: Preferences.State()) { Preferences() }
        }
    }

    @Test("Devices list, another device signs out, and this one can't be revoked from here")
    func devices() async {
        let server = DeviceServer()
        let store = makeStore(server)
        store.send(.devicesRequested)
        await settle("devices", until: { store.devices.value?.count == 2 })
        store.send(.deviceRevoked("aaaaaaaaaaaaaaaa"))
        store.send(.deviceRevoked("bbbbbbbbbbbbbbbb"))
        #expect(store.devices.value?.map(\.id) == ["aaaaaaaaaaaaaaaa"])
        await settle("revoked", until: { await server.revoked == ["bbbbbbbbbbbbbbbb"] })
    }

    @Test("Adding a device shows this Mac as a QR code that opens the app on its button")
    func addsDevice() async {
        let store = makeStore(DeviceServer())
        store.send(.addDeviceTapped)
        await settle("link", until: { store.connectLink != nil })
        #expect(store.connectLink?.mac == mini)
        store.send(.connectLinkDismissed)
        #expect(store.connectLink == nil)
    }

    @Test("A new business sends its brief and the starting team that stays switched on")
    func createsBusiness() async {
        let server = DeviceServer()
        let store = makeStore(server)
        store.send(.newBusinessTapped)
        guard var draft = store.newBusiness else { return #expect(Bool(false), "the sheet opens") }
        #expect(draft.team == Set(RoleTemplate.startingTeam))
        draft.name = " Globex "
        draft.brief = "Shared notes for families"
        draft.team.remove("growth")
        store.send(.newBusinessEdited(draft))
        store.send(.createBusinessTapped)
        await settle("created", until: { store.newBusiness == nil })
        #expect(await server.created == [NewBusiness(name: "Globex", brief: "Shared notes for families", team: ["engineering", "admin"])])
    }

    @Test("The owner's name saves trimmed; a blank one is refused here")
    func renames() async {
        let server = DeviceServer()
        let store = makeStore(server)
        await settle("owner", until: { store.ownerName == "Mitch" })
        store.send(.ownerRenamed("   "))
        #expect(store.errorText != nil)
        store.send(.ownerRenamed(" Mitch White "))
        await settle("renamed", until: { store.ownerName == "Mitch White" })
        #expect(await server.names == ["Mitch White"])
    }

    @Test("Editing a business sends only what changed")
    func editsBusiness() async {
        let server = DeviceServer()
        let store = makeStore(server)
        await settle("businesses", until: { !store.businesses.isEmpty })
        store.send(.businessSaved("acme", name: "Acme", brief: "Find classes nearby"))
        await settle("saved", until: { store.businesses.first?.brief == "Find classes nearby" })
        let update = await server.updates.first
        #expect(update == BusinessUpdate(id: "acme", name: nil, brief: "Find classes nearby"))
    }
}

private actor Answers {
    var answered: [(String, Bool)] = []
    var allowedKeys: [String] = []
    func answer(_ id: String, _ allow: Bool) { answered.append((id, allow)) }
    func allowKey(_ id: String) { allowedKeys.append(id) }
}

@MainActor
@Suite("Asked to join")
struct JoinPromptTests {
    private func makeStore(_ answers: Answers) -> StoreOf<Workspace> {
        let pending = DeviceKey(id: "k2", device: "bbbbbbbbbbbbbbbb", label: "Sam's iPhone", publicKey: "pk", status: .pending, createdAt: "2026-10-19T15:00:00Z")
        return withDependencies {
            $0.lookClient = .inert
            $0.profileClient = .inert
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                joins: { [JoinRequest(id: "j1", name: "Sam's iPhone", match: ["🦊", "🌵"])] },
                answerJoin: { id, allow in
                    await answers.answer(id, allow)
                    return allow ? pending : nil
                },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] }
            )
            $0.signingClient = SigningClient(
                enroll: { pending },
                approveSpend: { _ in },
                allow: { key, _ in await answers.allowKey(key.id) }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: mini.server)) { Workspace() }
        }
    }

    @Test("A device asking shows with its two emoji; Allow lets it in and this device endorses its key")
    func allows() async {
        let answers = Answers()
        let store = makeStore(answers)
        await settle("asked", until: { store.joinRequest?.match == ["🦊", "🌵"] && store.account != nil })
        #expect(store.joinRequest?.name == "Sam's iPhone")
        store.send(.joinAnswered("j1", allow: true))
        #expect(store.joinRequest == nil)
        await settle("allowed", until: { await answers.allowedKeys == ["k2"] })
        #expect(await answers.answered.map(\.1) == [true])
    }

    @Test("Deny answers once and endorses nothing")
    func denies() async {
        let answers = Answers()
        let store = makeStore(answers)
        await settle("asked", until: { store.joinRequest != nil })
        store.send(.joinAnswered("j1", allow: false))
        store.send(.joinAnswered("j1", allow: false))
        await settle("denied", until: { await answers.answered.count == 1 })
        #expect(await answers.answered.map(\.1) == [false])
        #expect(await answers.allowedKeys.isEmpty)
    }
}
