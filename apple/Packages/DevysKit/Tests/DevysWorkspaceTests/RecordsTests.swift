import DevysClient
import Testing
@testable import DevysWorkspace

@Suite("Record registry")
struct RecordsTests {
    private struct Apps: Decodable { let apps: [AppEntry] }

    @Test("The registry opens exactly the record kinds the apps' manifests declare")
    func matchesManifests() {
        let declared = Golden.decode(Apps.self, "apps").apps.flatMap { app in app.records.map { "\(app.id)/\($0.kind)" } }
        #expect(Set(Records.registry.keys) == Set(declared))
    }

    @Test("Pages and files open as layers anywhere; a coding session in its thread; work as places; anything else nowhere")
    func opens() {
        #expect(Records.open(.artifact("a1")) == .layer(.artifact("a1")))
        #expect(Records.open(.file("/b/plan.md")) == .layer(.file("/b/plan.md")))
        #expect(Records.open(.codeSession("s1")) == nil)
        #expect(Records.open(.codeSession("s1"), work: "w1") == .layer(.session(workID: "w1", sessionID: "s1")))
        #expect(Records.open(.workItem("w1")) == .place(.thread("w1")))
        #expect(Records.open(.workProject("p1")) == .place(.project("p1")))
        #expect(Records.open(.unknown(app: "mail", kind: "thread", id: "t1")) == nil)
        #expect(Layer(ref: .file("/b/plan.md")) == .file("/b/plan.md") && Layer(ref: .workItem("w1")) == nil)
    }
}
