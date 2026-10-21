import DevysClient
import Foundation
import Testing

/// The same cases as tests/ref.test.ts: the web and the server read refs exactly this way.
@Suite("Ref")
struct RefTests {
    @Test("A ref round-trips every kind, its id percent-encoded as encodeURIComponent does")
    func roundTrip() throws {
        let id = "a b/ü?#%"
        let all: [Ref] = [.artifact(id), .file(id), .codeSession(id), .workItem(id), .workProject(id)]
        #expect(all.map(\.description) == [
            "devys:documents/artifact/a%20b%2F%C3%BC%3F%23%25",
            "devys:documents/file/a%20b%2F%C3%BC%3F%23%25",
            "devys:code/session/a%20b%2F%C3%BC%3F%23%25",
            "devys:work/item/a%20b%2F%C3%BC%3F%23%25",
            "devys:work/project/a%20b%2F%C3%BC%3F%23%25"
        ])
        for ref in all { #expect(Ref(ref.description) == ref && ref.id == id) }
        let file = Ref.file("/Users/o/Devys/b1/plan (v2).md")
        #expect(file.description == "devys:documents/file/%2FUsers%2Fo%2FDevys%2Fb1%2Fplan%20(v2).md")
        #expect(Ref(file.description)?.id == "/Users/o/Devys/b1/plan (v2).md")
        #expect(Ref.artifact("-_.!~*'()").description == "devys:documents/artifact/-_.!~*'()")
        #expect(Ref("devys:work/item/w1") == .workItem("w1") && Ref("devys:work/item/w1")?.app == "work")
    }

    @Test("Parsing is strict: only the closed kinds, a non-empty id in the encoding a ref gives it")
    func rejects() {
        for value in [
            "artifact:123",
            "123",
            "devys:documents/artifact/",
            "devys:documents/page/1",
            "devys:code/item/1",
            "devys:mail/thread/1",
            "devys:documents/file//Users/o",
            "devys:documents/file/a%2",
            "devys:documents/file/a%2fb",
            "devys:documents/file/a b",
            "devys:Documents/artifact/1",
            "devys:documents/artifact/1/2",
            " devys:work/item/1",
            "devys:work/session/1",
            "devys:documents/file/a%+Fb",
            "devys:documents/file/%C3",
            "devys:documents/file/ü"
        ] {
            #expect(Ref(value) == nil, "\(value)")
        }
    }

    @Test("A ref is a JSON string; decoding anything else fails")
    func codable() throws {
        let encoded = try JSONEncoder().encode([Ref.workItem("w 1")])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["devys:work\/item\/w%201"]"#)
        #expect(try JSONDecoder().decode([Ref].self, from: encoded) == [.workItem("w 1")])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Ref].self, from: Data(#"["artifact:1"]"#.utf8)) }
    }
}
