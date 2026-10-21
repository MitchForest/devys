import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@MainActor
private func settle(_ what: String, until condition: @MainActor () -> Bool) async {
    for _ in 0..<8_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(what)")
}

/// What the server and this device's signer were asked to do.
private actor AskServer {
    var home: Home
    var signed: [SpendApproval] = []
    var takeovers: [(String, Bool)] = []
    var refusal: (any Error & Sendable)?

    init(home: Home) { self.home = home }

    func sign(_ approval: SpendApproval) throws {
        if let refusal { throw refusal }
        signed.append(approval)
        home = home.answering(approval.decisionID)
    }

    func refuse(_ error: any Error & Sendable) { refusal = error }
    func takeOver(_ id: String, _ taking: Bool) { takeovers.append((id, taking)) }
}

private let spend = Decision(
    id: "d-spend",
    kind: .approve,
    employeeID: "growth",
    capability: "askOwner",
    input: .object([
        "kind": .string("approve"),
        "action": .string("Register acme.example for one year"),
        "counterparty": .string("Namecheap"),
        "amount": .object(["cents": .number(1299), "currency": .string("USD")]),
        "renewal": .string("Renews yearly at $14.99")
    ]),
    workItemID: "c1",
    expiresAt: "2026-10-22T09:30:00.000Z"
)

private let signIn = Decision(
    id: "d-sign-in",
    kind: .takeOver,
    employeeID: "growth",
    capability: "askOwner",
    input: .object(["kind": .string("take_over"), "reason": .string("Sign in to the registrar (2FA)")]),
    workItemID: "c1"
)

@MainActor
@Suite("Asking the owner")
struct AskingFeatureTests {
    private func makeStore(_ server: AskServer) -> StoreOf<Workspace> {
        withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { _ in .fixture },
                stop: { _ in true },
                memory: { _ in [] },
                work: { _ in [WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Register the domain", state: .inProgress)] },
                setTakeover: { _, id, taking in await server.takeOver(id, taking) },
                home: { _ in await server.home }
            )
            // A mock signer: no Secure Enclave or Face ID in tests.
            $0.signingClient = SigningClient(
                enroll: { DeviceKey(id: "k1", device: "0123456789abcdef", publicKey: "", status: .active, current: true) },
                approveSpend: { try await server.sign($0) },
                allow: { _, _ in },
                biometry: { "Touch ID" }
            )
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
    }

    @Test("Approve on a spend opens the signing sheet with exactly the spend; signing sends it once and closes it")
    func signs() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(spend, title: "Register the domain")]))
        let store = makeStore(server)
        await settle("home", until: { store.state.decisions.count == 1 })
        store.send(.signTapped("d-spend"))
        let sheet = store.signing
        #expect(sheet?.approval.counterparty == "Namecheap" && sheet?.approval.amount.text == "$12.99")
        #expect(sheet?.approval.renewal == "Renews yearly at $14.99" && sheet?.approval.action == "Register acme.example for one year")
        #expect(sheet?.employee.isEmpty == false)
        #expect(sheet?.biometry == "Touch ID" && sheet?.approval.workItemID == "c1")
        store.send(.signConfirmed)
        store.send(.signConfirmed)
        await settle("signed", until: { store.signing == nil })
        let signed = await server.signed
        #expect(signed.count == 1 && signed.first?.decisionID == "d-spend" && signed.first?.businessID == store.businessID)
        #expect(store.state.decisions.isEmpty)
    }

    @Test("A cancelled Face ID or a refused signature keeps the sheet open and says why")
    func refused() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(spend, title: "Register the domain")]))
        await server.refuse(SigningError.cancelled)
        let store = makeStore(server)
        await settle("home", until: { store.state.decisions.count == 1 })
        store.send(.signTapped("d-spend"))
        store.send(.signConfirmed)
        await settle("refused", until: { store.signing?.error != nil })
        #expect(store.signing?.error == "Not signed." && store.signing?.isSigning == false)
        await server.refuse(SigningError.notAllowed)
        store.send(.signConfirmed)
        await settle("not allowed", until: { store.signing?.error?.contains("Settings › Devices") == true })
        store.send(.signDismissed)
        #expect(store.signing == nil && store.state.decisions.count == 1)
    }

    @Test("Approve on anything but a spend never opens the signing sheet")
    func onlySpends() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(signIn, title: "Register the domain")]))
        let store = makeStore(server)
        await settle("home", until: { store.state.decisions.count == 1 })
        store.send(.signTapped("d-sign-in"))
        #expect(store.signing == nil)
    }

    @Test("Take over on a take-over request takes the work over and opens its live browser beside the thread")
    func takesOver() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(signIn, title: "Register the domain")]))
        let store = makeStore(server)
        await settle("home", until: { store.home.value?.needsYou.first?.kind == .takeOver })
        store.send(.takeOverTapped("c1"))
        #expect(store.place == .thread("c1") && store.state.topLayer == .browser(workID: "c1"))
        for _ in 0..<2_000 where await server.takeovers.isEmpty { await Task.yield() }
        let takeovers = await server.takeovers
        #expect(takeovers.count == 1 && takeovers.first?.0 == "c1" && takeovers.first?.1 == true)
    }
}
