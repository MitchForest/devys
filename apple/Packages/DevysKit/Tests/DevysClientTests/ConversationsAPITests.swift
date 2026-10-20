import DevysClient
import Foundation
import Testing

@Suite("Conversations API")
struct ConversationsAPITests {
    private actor Recorder {
        var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
    }

    private static let session = DeviceSession(server: URL(string: "https://devys.test")!, token: "tok")

    private func api(status: Int = 200, body: String, recorder: Recorder) -> DevysHTTPClient {
        DevysHTTPClient { request in
            await recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private func lastBody(_ recorder: Recorder) async throws -> [String: Any] {
        let request = try #require(await recorder.requests.last)
        return try #require(try request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    }

    private static let message = """
    {"id":"m2","conversation":"space:s1","author":"employee:growth","kind":"message","text":"On it.","reply_to":"m1",
     "mentions":["ops"],"via_voice":false,"ref":null,"created_at":"2026-10-19T15:00:05.123456+00:00"}
    """

    @Test("Keys parse and print as kind:ref; anything else is refused")
    func keys() {
        #expect(ConversationKey("direct:ops") == .direct("ops"))
        #expect(ConversationKey("work:c-1")?.ref == "c-1")
        #expect(ConversationKey.space("s1").rawValue == "space:s1")
        #expect(ConversationKey("group:x") == nil)
        #expect(ConversationKey("direct:") == nil)
        #expect(ConversationKey("ops") == nil)
    }

    @Test("The list decodes each started conversation's newest message and unread count")
    func list() async throws {
        let recorder = Recorder()
        let summaries = try await api(
            body: #"{"conversations":[{"key":"space:s1","last":\#(Self.message),"unread":2,"following":false},{"key":"work:c1","last":null,"unread":0,"following":true}]}"#,
            recorder: recorder
        ).conversations(Self.session, businessID: "b1")
        #expect(summaries.map(\.key) == ["space:s1", "work:c1"])
        #expect(summaries[0].unread == 2)
        #expect(summaries.map(\.following) == [false, true])
        #expect(summaries[0].last?.employeeID == "growth")
        #expect(summaries[1].last == nil)
        let request = try #require(await recorder.requests.last)
        #expect(request.url?.absoluteString == "https://devys.test/api/businesses/b1/conversations")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer tok")
    }

    @Test("A page decodes messages with reactions, events and the respondent; the key is encoded and `before` pages back")
    func page() async throws {
        let recorder = Recorder()
        let body = """
        {"respondent":"growth","messages":[
          {"id":"m1","conversation":"space:s1","author":"person:p1","kind":"message","text":"@Growth status?","reply_to":null,
           "mentions":["growth"],"via_voice":true,"ref":null,"created_at":"2026-10-19T15:00:00.000Z","reactions":[]},
          {"id":"m2","conversation":"space:s1","author":"employee:growth","kind":"message","text":"On it.","reply_to":"m1",
           "mentions":[],"via_voice":false,"ref":null,"created_at":"2026-10-19T15:00:05.000Z","reactions":["👍"]},
          {"id":"m3","conversation":"space:s1","author":"system","kind":"event","text":"Growth took on \\"Write a tagline\\".",
           "reply_to":null,"mentions":[],"via_voice":false,"ref":"c9","created_at":"2026-10-19T15:00:06.000Z","reactions":[]}]}
        """
        let page = try await api(body: body, recorder: recorder)
            .conversation(Self.session, businessID: "b1", key: .space("s1"), before: "m9")
        #expect(page.respondent == "growth")
        #expect(page.messages.map(\.id) == ["m1", "m2", "m3"])
        #expect(page.messages[0].isFromPerson && page.messages[0].viaVoice && page.messages[0].mentions == ["growth"])
        #expect(page.messages[1].employeeID == "growth" && page.messages[1].replyTo == "m1" && page.messages[1].reactions == ["👍"])
        #expect(page.messages[2].isEvent && page.messages[2].ref == "c9" && page.messages[2].employeeID == nil)
        #expect(page.messages[0].date != nil)
        let request = try #require(await recorder.requests.last)
        #expect(request.url?.absoluteString == "https://devys.test/api/businesses/b1/conversations/space%3As1?before=m9")
        #expect(request.httpMethod == "GET")
    }

    @Test("Microsecond timestamps with an offset still parse")
    func timestamps() throws {
        let message = try JSONDecoder().decode(ConversationMessage.self, from: Data(Self.message.utf8))
        let expected = try #require(ServerDate.parse("2026-10-19T15:00:05.123Z"))
        #expect(abs(try #require(message.date).timeIntervalSince(expected)) < 0.001)
        #expect(message.reactions.isEmpty)
    }

    @Test("Posting sends the client id, reply, mentions and voice, and decodes who answers")
    func post() async throws {
        let recorder = Recorder()
        let posted = try await api(status: 201, body: #"{"message":\#(Self.message),"to":["growth"]}"#, recorder: recorder)
            .postMessage(Self.session, businessID: "b1", key: .direct("growth"), NewMessage(id: "c-0001", text: "Go", replyTo: "m1", mentions: ["growth"], viaVoice: true))
        #expect(posted.recipients == ["growth"])
        #expect(posted.message.id == "m2")
        let request = try #require(await recorder.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://devys.test/api/businesses/b1/conversations/direct%3Agrowth/messages")
        let body = try await lastBody(recorder)
        #expect(body["id"] as? String == "c-0001" && body["text"] as? String == "Go")
        #expect(body["replyTo"] as? String == "m1" && body["mentions"] as? [String] == ["growth"] && body["viaVoice"] as? Bool == true)

        _ = try await api(status: 201, body: #"{"message":\#(Self.message),"to":[]}"#, recorder: recorder)
            .postMessage(Self.session, businessID: "b1", key: .work("c1"), NewMessage(id: "c-0002", text: "Hi"))
        let plain = try await lastBody(recorder)
        #expect(plain.keys.sorted() == ["id", "text", "viaVoice"])
    }

    @Test("A paused answerer comes back as 409 with the server's words")
    func paused() async throws {
        let recorder = Recorder()
        await #expect(throws: DevysHTTPError.rejected(status: 409, message: "Growth is paused. Resume them to send.")) {
            _ = try await api(status: 409, body: "Growth is paused. Resume them to send.", recorder: recorder)
                .postMessage(Self.session, businessID: "b1", key: .direct("growth"), NewMessage(id: "c-0003", text: "Hi"))
        }
    }

    @Test("Marking read posts the newest message's time")
    func read() async throws {
        let recorder = Recorder()
        try await api(body: #"{"read":true}"#, recorder: recorder)
            .markRead(Self.session, businessID: "b1", key: .space("s1"), at: "2026-10-19T15:00:05.000Z")
        let request = try #require(await recorder.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://devys.test/api/businesses/b1/conversations/space%3As1/read")
        #expect(try await lastBody(recorder)["at"] as? String == "2026-10-19T15:00:05.000Z")
    }
}
