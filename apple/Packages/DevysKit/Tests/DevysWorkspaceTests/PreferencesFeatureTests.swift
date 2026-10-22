import ComposableArchitecture2
import DevysCharacter
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@MainActor
@Suite("Preferences")
struct PreferencesFeatureTests {
    private actor Box {
        var looks: [LookTarget: Look?] = [:]
        var uploads: [Data] = []
        func set(_ target: LookTarget, _ look: Look?) { looks[target] = .some(look) }
        func upload(_ data: Data) { uploads.append(data) }
    }

    private func makeStore(box: Box, uploadFails: Bool = false) -> StoreOf<Preferences> {
        withDependencies {
            $0.lookClient = LookClient(
                set: { target, look in await box.set(target, look) },
                importPhoto: { _, _ in },
                photo: { _ in nil }
            )
            $0.profileClient = ProfileClient(
                photo: { nil },
                upload: { data in
                    if uploadFails { throw DevysHTTPError.unreachable("offline") }
                    await box.upload(data)
                },
                remove: {}
            )
            $0.runtimeClient = .fixture
        } operation: {
            Store(initialState: Preferences.State()) { Preferences() }
        }
    }

    private func settle(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<4_000 where await !condition() { await Task.yield() }
    }

    @Test("Loads every business's team and selects the first employee")
    func loadsTeams() async {
        let store = makeStore(box: Box())
        await settle { store.ownerName != nil }
        #expect(store.businesses.map(\.id) == ["acme", "globex"])
        #expect(store.selectedEmployeeID == WorkspaceSnapshot.acmeLaunch.employees.first?.id)
        #expect(store.ownerName == "Mitch")
    }

    @Test("Choosing a look and resetting it reach the server, and show at once")
    func setsLooks() async {
        let box = Box()
        let store = makeStore(box: box)
        await settle { !store.businesses.isEmpty }
        let growth = LookTarget.employee(business: "acme", employee: "growth")
        store.send(.lookSet(growth, .emoji("📈", tint: "orange")))
        #expect(store.teams["acme"]?.first { $0.id == "growth" }?.look == .emoji("📈", tint: "orange"))
        store.send(.lookSet(.business("acme"), nil))
        await settle { await box.looks.count == 2 }
        #expect(await box.looks[growth] == .some(.emoji("📈", tint: "orange")))
        #expect(await box.looks[.business("acme")] == .some(nil))
        #expect(store.state.target(forEmployee: "growth") == growth)
    }

    @Test("A failed profile upload shows a fix, not a spinner")
    func uploadFailure() async {
        let store = makeStore(box: Box(), uploadFails: true)
        store.send(.ownerPhotoPicked(Data([1])))
        await settle { store.errorText != nil }
        #expect(!store.isUploading)
        #expect(store.errorText?.contains("connection") == true)
    }

    private actor Vault {
        var entries: [String: [SecretEntry]] = ["acme": [SecretEntry(name: "STRIPE_KEY", kind: .secret)]]
        var sent: [NewSecret] = []
        func add(_ business: String, _ secret: NewSecret) -> [SecretEntry] {
            sent.append(secret)
            let kind: SecretEntry.Kind = if case .card = secret.value { .spend } else { .secret }
            entries[business, default: []].append(SecretEntry(name: secret.name, kind: kind))
            return entries[business] ?? []
        }
        func remove(_ business: String, _ name: String) -> [SecretEntry] {
            entries[business]?.removeAll { $0.name == name }
            return entries[business] ?? []
        }
        func list(_ business: String) -> [SecretEntry] { entries[business] ?? [] }
    }

    @Test("Settings › Secrets lists names, adds one through the secure sheet and removes one; no value stays in state")
    func secrets() async {
        let vault = Vault()
        var runtime = RuntimeClient.fixture
        runtime.secrets = { await vault.list($0) }
        runtime.addSecret = { await vault.add($0, $1) }
        runtime.removeSecret = { await vault.remove($0, $1) }
        let store = withDependencies {
            $0.lookClient = LookClient(set: { _, _ in }, importPhoto: { _, _ in }, photo: { _ in nil })
            $0.profileClient = ProfileClient(photo: { nil }, upload: { _ in }, remove: {})
            $0.runtimeClient = runtime
        } operation: {
            Store(initialState: Preferences.State()) { Preferences() }
        }
        await settle { !store.businesses.isEmpty }
        store.send(.secretsRequested)
        await settle { store.secrets.value != nil }
        #expect(store.secrets.value?.map(\.name) == ["STRIPE_KEY"])

        store.send(.addSecretTapped)
        #expect(store.secretEntry?.isFixed == false)
        var sheet = store.secretEntry!
        sheet.name = "GITHUB_TOKEN"
        store.send(.secretEdited(sheet))
        store.send(.secretSubmitted(NewSecret(name: "GITHUB_TOKEN", value: .secret("ghp_hidden_value"))))
        await settle { store.secretEntry == nil }
        #expect(await vault.sent == [NewSecret(name: "GITHUB_TOKEN", value: .secret("ghp_hidden_value"))])
        #expect(store.secrets.value?.map(\.name) == ["STRIPE_KEY", "GITHUB_TOKEN"])
        #expect(!String(describing: store.state).contains("ghp_hidden_value"))

        store.send(.secretRemoved("STRIPE_KEY"))
        #expect(store.secrets.value?.map(\.name) == ["GITHUB_TOKEN"])
        await settle { await vault.list("acme").count == 1 }
        #expect(await vault.list("acme").map(\.name) == ["GITHUB_TOKEN"])
    }
}
