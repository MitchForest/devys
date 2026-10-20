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

private actor SignIns {
    var calls: [(URL, String)] = []
    func record(_ server: URL, _ code: String) { calls.append((server, code)) }
}

nonisolated private let hex = String(repeating: "c0", count: 32)
nonisolated private let link = URL(string: "devys://enroll?server=http%3A%2F%2Fmac-mini.tail.ts.net%3A5173&code=\(hex)")!
nonisolated private let home = URL(string: "http://127.0.0.1:5173")!

@MainActor
@Suite("Enroll links")
struct EnrollLinkTests {
    private func makeStore(_ signIns: SignIns, phases: AsyncStream<SessionPhase>) -> StoreOf<DevysApp> {
        withDependencies {
            $0.sessionClient = SessionClient(
                phases: { phases },
                signIn: { server, code in await signIns.record(server, code) },
                signOut: {},
                expire: {}
            )
            $0.runtimeClient = .fixture
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: DevysApp.State()) { DevysApp() }
        }
    }

    @Test("Signed out, a link signs in with its server and code at once")
    func signsIn() async {
        let signIns = SignIns()
        let (phases, continuation) = AsyncStream<SessionPhase>.makeStream()
        let store = makeStore(signIns, phases: phases)
        continuation.yield(.signedOut)
        await settle("signed out", until: { store.route == .signedOut })
        store.send(.linkOpened(link))
        #expect(store.pendingLink == nil)
        await settle("signed in", until: { await signIns.calls.count == 1 && !store.isEnrolling })
        let call = await signIns.calls.first
        #expect(call?.0.absoluteString == "http://mac-mini.tail.ts.net:5173")
        #expect(call?.1 == hex)
    }

    @Test("Signed in, a link asks first; confirming replaces the session and starts the workspace fresh")
    func replacesAfterConfirming() async {
        let signIns = SignIns()
        let (phases, continuation) = AsyncStream<SessionPhase>.makeStream()
        let store = makeStore(signIns, phases: phases)
        continuation.yield(.signedIn(server: home))
        await settle("signed in", until: { store.route == .signedIn })
        store.send(.linkOpened(link))
        #expect(store.pendingLink?.code == hex)
        store.send(.linkCancelled)
        #expect(store.pendingLink == nil)
        for _ in 0..<200 { await Task.yield() }
        #expect(await signIns.calls.isEmpty)
        store.send(.linkOpened(link))
        store.send(.linkConfirmed)
        await settle("replaced", until: { await signIns.calls.count == 1 && !store.isEnrolling })
        #expect(store.spawn(\.workspace)?.server.host() == "mac-mini.tail.ts.net")
    }

    @Test("Anything but a sign-in link says so")
    func refusesOtherLinks() {
        let store = makeStore(SignIns(), phases: AsyncStream { $0.finish() })
        store.send(.linkOpened(URL(string: "devys://enroll?code=abc")!))
        #expect(store.linkError != nil)
        store.send(.linkErrorDismissed)
        #expect(store.linkError == nil)
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

    func revoke(_ id: String) {
        revoked.append(id)
        devices.removeAll { $0.id == id }
    }
    func create(_ business: NewBusiness) -> Business {
        created.append(business)
        return Business(id: "new", name: business.name, brief: business.brief)
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
                business: { BusinessDetail.fixture($0) },
                createBusiness: { await server.create($0) },
                updateBusiness: { await server.update($0, $1, $2) },
                devices: { await server.devices },
                issueDeviceCode: { DeviceCode(code: hex, expiresAt: Date.now.addingTimeInterval(600), server: home) },
                revokeDevice: { await server.revoke($0) },
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

    @Test("Adding a device issues a code whose link opens this server")
    func addsDevice() async {
        let store = makeStore(DeviceServer())
        store.send(.addDeviceTapped)
        await settle("code", until: { store.deviceCode != nil })
        #expect(store.deviceCode?.link.url.absoluteString == "devys://enroll?server=http%3A%2F%2F127.0.0.1%3A5173&code=\(hex)")
        store.send(.deviceCodeDismissed)
        #expect(store.deviceCode == nil)
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
        #expect(await server.created == [NewBusiness(name: "Globex", brief: "Shared notes for families", team: ["engineering", "business-operations"])])
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
