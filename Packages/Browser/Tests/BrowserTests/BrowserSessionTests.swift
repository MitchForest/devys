import Foundation
import Testing
import WebKit
@testable import Browser

@Suite("BrowserSession Tests")
struct BrowserSessionTests {
    @Test("Hosted web view teardown clears delegates and stale-state tracking")
    @MainActor
    func hostedWebViewTeardown() throws {
        let initialURL = try #require(URL(string: "http://localhost:3000"))
        let session = BrowserSession(url: initialURL)
        let webView = session.ensureWebView()
        let delegate = NavigationDelegateSpy()

        session.setNavigationDelegate(delegate)
        #expect(webView.navigationDelegate as AnyObject? === delegate)
        #expect(session.isManaging(webView))

        session.beginRemoval()
        #expect(!session.isManaging(webView))

        session.dismantleHostedWebView(webView)

        #expect(webView.navigationDelegate == nil)
        #expect(webView.uiDelegate == nil)
        #expect(!session.isManaging(webView))
    }
}

private final class NavigationDelegateSpy: NSObject, WKNavigationDelegate {}
