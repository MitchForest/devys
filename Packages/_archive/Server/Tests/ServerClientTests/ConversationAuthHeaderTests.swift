import Foundation
import XCTest
import ServerProtocol
@testable import ServerClient

final class ConversationAuthHeaderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.setHandler(nil)
        super.tearDown()
    }

    func testConversationListIncludesBearerTokenWhenProvided() async throws {
        let expectedToken = "token-123"
        URLProtocolStub.setHandler { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(expectedToken)")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = try ServerJSONCoding.makeEncoder().encode(SessionListResponse(sessions: []))
            return (response, data)
        }

        let client = ServerClient(session: Self.makeStubbedSession())
        _ = try await client.listConversationSessions(
            baseURL: URL(string: "http://127.0.0.1:8787")!,
            authToken: expectedToken
        )
    }

    func testConversationListOmitsAuthorizationWhenTokenNotProvided() async throws {
        URLProtocolStub.setHandler { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = try ServerJSONCoding.makeEncoder().encode(SessionListResponse(sessions: []))
            return (response, data)
        }

        let client = ServerClient(session: Self.makeStubbedSession())
        _ = try await client.listConversationSessions(baseURL: URL(string: "http://127.0.0.1:8787")!)
    }

    private static func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static nonisolated(unsafe) var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let currentHandler = Self.handler
        Self.lock.unlock()

        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try currentHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
