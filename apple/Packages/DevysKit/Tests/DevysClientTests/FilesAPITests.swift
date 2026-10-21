import CoreGraphics
import DevysClient
import Foundation
import Testing

@Suite("Files API")
struct FilesAPITests {
    private actor Recorder {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
    }

    private static let session = DeviceSession(server: URL(string: "https://devys.test")!, token: "tok")

    private func api(status: Int = 200, body: String, headers: [String: String]? = nil, recorder: Recorder) -> DevysHTTPClient {
        DevysHTTPClient { request in
            await recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }

    @Test("A listing marks repositories, which belong to Code; coding work lists newest first")
    func repositories() async throws {
        let recorder = Recorder()
        let listing = try await api(
            body: #"{"root":"/b","path":"/b","entries":[{"name":"site","path":"/b/site","kind":"repository","size":0},{"name":"plan.md","path":"/b/plan.md","kind":"file","size":12}]}"#,
            recorder: recorder
        ).files(Self.session, businessID: "b", path: nil)
        #expect(listing.entries.map(\.kind) == [.repository, .file])
        let work = try await api(body: #"{"work":["c2","c1"]}"#, recorder: recorder).codingWork(Self.session, businessID: "b")
        #expect(work == ["c2", "c1"])
        #expect(await recorder.requests.last?.url?.path() == "/api/businesses/b/coding")
    }

    @Test("A stale save comes back as a conflict with the newer text")
    func staleSave() async throws {
        let recorder = Recorder()
        let body = ##"{"conflict":true,"current":{"path":"/d/plan.md","content":"# Newer\n","revision":"r2"}}"##
        let result = try await api(status: 409, body: body, recorder: recorder)
            .saveFile(Self.session, businessID: "b", path: "/d/plan.md", content: "# Mine\n", expectedRevision: "r1")
        #expect(result == .conflict(FileText(path: "/d/plan.md", content: "# Newer\n", revision: "r2")))
        let sent = try #require(try await recorder.requests.last?.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(sent["expectedRevision"] as? String == "r1")
    }

    @Test("Bytes come with their revision and save over it; a derived copy overwrites")
    func bytes() async throws {
        let recorder = Recorder()
        let read = try await api(body: "PK", headers: ["x-devys-revision": "r1"], recorder: recorder)
            .fileBytes(Self.session, businessID: "b", path: "/d/budget.xlsx")
        #expect(read == FileBytes(data: Data("PK".utf8), revision: "r1"))
        let saved = try await api(body: ##"{"path":"/d/budget.xlsx","revision":"r2"}"##, recorder: recorder)
            .saveFileBytes(Self.session, businessID: "b", path: "/d/budget.xlsx", data: Data("PK2".utf8), expected: .revision("r1"))
        #expect(saved == .saved(revision: "r2"))
        let request = try #require(await recorder.requests.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.httpBody == Data("PK2".utf8))
        #expect(request.url?.query == "path=/d/budget.xlsx&expectedRevision=r1")
        let stale = try await api(status: 409, body: ##"{"conflict":true}"##, recorder: recorder)
            .saveFileBytes(Self.session, businessID: "b", path: "/d/budget.xlsx", data: Data(), expected: .revision("r1"))
        #expect(stale == .conflict(nil))
        _ = try await api(body: ##"{"path":"/d/deck.pptx","revision":"r3"}"##, recorder: recorder)
            .saveFileBytes(Self.session, businessID: "b", path: "/d/deck.pptx", data: Data(), expected: .overwrite)
        #expect(await recorder.requests.last?.url?.query == "path=/d/deck.pptx")
    }

    @Test("Comments carry their anchors; paths are encoded in the query")
    func comments() async throws {
        let recorder = Recorder()
        let client = api(body: "{}", recorder: recorder)
        try await client.commentOnFile(Self.session, businessID: "b", path: "/d/a b&c.pdf", employee: "e", comments: [
            FileComment(anchor: .pdf(page: 2, rects: [CGRect(x: 1, y: 2, width: 3, height: 4)]), text: "Wrong"),
            FileComment(anchor: .text(start: 0, end: 4, quote: "Goal"), text: "First")
        ])
        let sent = try #require(try await recorder.requests.last?.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let comments = try #require(sent["comments"] as? [[String: Any]])
        #expect((comments[0]["anchor"] as? [String: Any])?["page"] as? Int == 2)
        #expect((comments[1]["anchor"] as? [String: Any])?["quote"] as? String == "Goal")
        _ = try? await client.fileBytes(Self.session, businessID: "b", path: "/d/a b&c.pdf")
        #expect(await recorder.requests.last?.url?.query == "path=/d/a%20b%26c.pdf")
    }
}
