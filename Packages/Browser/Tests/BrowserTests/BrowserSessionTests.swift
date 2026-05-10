import Foundation
import Testing
import WebKit
@testable import Browser

@Suite("BrowserSession Tests")
struct BrowserSessionTests {
    @Test("Localhost URL strings default to http")
    @MainActor
    func localhostURLStringDefaultsToHTTP() throws {
        let initialURL = try #require(URL(string: "http://localhost:3000"))
        let session = BrowserSession(url: initialURL)

        session.load(urlString: "localhost:5173")

        #expect(session.url == URL(string: "http://localhost:5173"))
    }

    @Test("Local file loads update session URL")
    @MainActor
    func localFileLoadUpdatesSessionURL() throws {
        let initialURL = try #require(URL(string: "http://localhost:3000"))
        let fileURL = URL(fileURLWithPath: "/tmp/devys-browser/index.html")
        let readAccessURL = URL(fileURLWithPath: "/tmp/devys-browser", isDirectory: true)
        let session = BrowserSession(url: initialURL)

        session.loadFile(url: fileURL, allowingReadAccessTo: readAccessURL)

        #expect(session.url == fileURL.standardizedFileURL)
    }

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
