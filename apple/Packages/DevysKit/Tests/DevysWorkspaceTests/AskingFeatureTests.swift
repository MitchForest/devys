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

    var added: [(business: String, secret: NewSecret)] = []

    func add(_ business: String, _ secret: NewSecret) throws -> [SecretEntry] {
        if let refusal { throw refusal }
        added.append((business, secret))
        // The server answers the request once the named secret exists.
        if let request = home.decisions.first(where: { if case .secret(secret.name, _, _) = $0.request { true } else { false } }) {
            home = home.answering(request.id)
        }
        return [SecretEntry(name: secret.name, kind: .spend)]
    }

    var files: [(decision: String, file: ChosenFile)] = []

    func send(_ decision: String, _ file: ChosenFile) {
        files.append((decision, file))
        home = home.answering(decision)
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

private let cardRequest = Decision(
    id: "d-card",
    kind: .secret,
    employeeID: "growth",
    capability: "askOwner",
    input: .object([
        "kind": .string("secret"),
        "name": .string("RAMP_CARD"),
        "why": .string("The company card, for the domain"),
        "spend": .bool(true)
    ]),
    workItemID: "c1"
)

private let logoRequest = Decision(
    id: "d-logo",
    kind: .file,
    employeeID: "growth",
    capability: "askOwner",
    input: .object([
        "kind": .string("file"),
        "purpose": .string("Your logo, for the site"),
        "accept": .array([.string("image/*")])
    ]),
    workItemID: "c1"
)

private let shipRequest = Decision(
    id: "d-ship",
    kind: .approve,
    employeeID: "growth",
    capability: "askOwner",
    input: .object([
        "kind": .string("approve"),
        "action": .string("Merge and ship the waitlist page"),
        "counterparty": .string("github.com/acme/site"),
        "steps": .array([.string("Merge PR #12 at a1b2c3"), .string("Deploy a1b2c3 of site to production")]),
        "preview": .string("devys:documents/artifact/00000000-0000-4000-8000-000000000005"),
        "previewHash": .string(String(repeating: "d", count: 64))
    ]),
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
                sendFile: { _, decision, file in await server.send(decision, file) },
                home: { _ in await server.home },
                addSecret: { id, secret in try await server.add(id, secret) }
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

    @Test("A secret request opens the secure entry sheet for that name; the value goes to the vault, never into state")
    func addsSecret() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(cardRequest, title: "Register the domain")]))
        let store = makeStore(server)
        await settle("home", until: { store.home.value?.needsYou.first?.kind == .secret })
        // The owner reads what it is; the name is the employee's.
        #expect(DecisionText.title(cardRequest) == "Your card")
        #expect(!DecisionText.fields(cardRequest).contains { $0.value.contains("RAMP_CARD") })
        store.send(.secretTapped("d-card"))
        let sheet = store.secretEntry
        #expect(sheet?.name == "RAMP_CARD" && sheet?.isCard == true && sheet?.isFixed == true && sheet?.why == "The company card, for the domain")
        // A different name than the request's is not sent.
        store.send(.secretSubmitted(NewSecret(name: "OTHER", value: .secret("x"))))
        #expect(store.secretEntry?.isSaving == false)
        let card = CardEntry(number: "4242424242424242", expiry: "04/31", cvc: "737", name: "Sam Owner", postal: "94107")
        store.send(.secretSubmitted(NewSecret(name: "RAMP_CARD", value: .card(card))))
        #expect(store.secretEntry?.isSaving == true)
        await settle("added", until: { store.secretEntry == nil })
        let added = await server.added
        #expect(added.count == 1 && added.first?.business == store.businessID && added.first?.secret.value == .card(card))
        #expect(store.state.decisions.isEmpty)
        #expect(!String(describing: store.state).contains("4242424242424242"))
    }

    @Test("A take over reads its reason once; a combined approval lists its steps and its draft")
    func readsRequests() {
        #expect(DecisionText.title(signIn) == "Sign in to the registrar (2FA)")
        #expect(DecisionText.fields(signIn).isEmpty)
        #expect(shipRequest.steps == ["Merge PR #12 at a1b2c3", "Deploy a1b2c3 of site to production"])
        #expect(shipRequest.preview == .artifact("00000000-0000-4000-8000-000000000005"))
        #expect(logoRequest.request == .file(purpose: "Your logo, for the site", accept: ["image/*"]))
        #expect(DecisionText.title(logoRequest) == "Your logo, for the site")
    }

    @Test("A file request is answered with the chosen file, once, and leaves Needs you")
    func sendsFile() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(logoRequest, title: "Register the domain")]))
        let store = makeStore(server)
        await settle("home", until: { store.home.value?.needsYou.first?.kind == .file })
        let logo = ChosenFile(name: "logo.png", type: "image/png", data: Data([1, 2, 3]))
        store.send(.fileChosen("d-logo", logo))
        #expect(store.state.decisions.isEmpty)
        for _ in 0..<2_000 where await server.files.isEmpty { await Task.yield() }
        let files = await server.files
        #expect(files.count == 1 && files.first?.decision == "d-logo" && files.first?.file == logo)
    }

    @Test("A refused secret keeps the sheet open with the server's reason")
    func secretRefused() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(cardRequest, title: "Register the domain")]))
        await server.refuse(DevysHTTPError.rejected(status: 400, message: "That card number isn't valid; check it and try again"))
        let store = makeStore(server)
        await settle("home", until: { store.state.decisions.count == 1 })
        store.send(.secretTapped("d-card"))
        let card = CardEntry(number: "4242424242424241", expiry: "04/31", cvc: nil, name: "Sam", postal: "94107")
        store.send(.secretSubmitted(NewSecret(name: "RAMP_CARD", value: .card(card))))
        await settle("refused", until: { store.secretEntry?.error != nil })
        #expect(store.secretEntry?.error == "That card number isn't valid; check it and try again" && store.secretEntry?.isSaving == false)
        store.send(.secretDismissed)
        #expect(store.secretEntry == nil && store.state.decisions.count == 1)
    }

    @Test("Approve is never what answers a secret request; approve on it opens no signing sheet")
    func secretNotApproved() async {
        let server = AskServer(home: Home(needsYou: [NeedsYouItem(cardRequest, title: "Register the domain")]))
        let store = makeStore(server)
        await settle("home", until: { store.state.decisions.count == 1 })
        store.send(.signTapped("d-card"))
        #expect(store.signing == nil && !cardRequest.isSpend)
    }
}
