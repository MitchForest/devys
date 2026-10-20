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
        #expect(store.businesses.map(\.id) == ["acme", "scribble"])
        #expect(store.selectedEmployeeID == WorkspacePreview.acmeLaunch.employees.first?.id)
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
}
