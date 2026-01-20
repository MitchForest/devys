import Foundation
import WebKit
import Observation

/// Observable store bridging WKWebView state to SwiftUI.
///
/// Tracks navigation state and provides control methods for the webview.
@MainActor
@Observable
public final class WebViewStore {
    // MARK: - State

    /// Current URL
    public var currentURL: URL

    /// Page title
    public var title: String = ""

    /// Whether browser can go back
    public var canGoBack: Bool = false

    /// Whether browser can go forward
    public var canGoForward: Bool = false

    /// Whether page is loading
    public var isLoading: Bool = false

    /// Load progress (0.0 to 1.0)
    public var loadProgress: Double = 0

    /// Error message if load failed
    public var errorMessage: String?

    // MARK: - WebView Reference

    /// Weak reference to the managed WKWebView
    public weak var webView: WKWebView?

    // MARK: - Callbacks

    /// Called when title changes
    public var onTitleChange: ((String) -> Void)?

    // MARK: - Initialization

    public init(initialURL: URL = URL(string: "http://localhost:3000")!) {  // swiftlint:disable:this force_unwrapping
        self.currentURL = initialURL
    }

    // MARK: - Navigation Methods

    public func goBack() {
        webView?.goBack()
    }

    public func goForward() {
        webView?.goForward()
    }

    public func reload() {
        webView?.reload()
    }

    public func stopLoading() {
        webView?.stopLoading()
    }

    public func load(url: URL) {
        currentURL = url
        errorMessage = nil
        webView?.load(URLRequest(url: url))
    }

    public func load(urlString: String) {
        guard let url = BrowserState.normalizeURLString(urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        load(url: url)
    }

    // MARK: - State Updates (called by Coordinator)

    func updateNavigationState(from webView: WKWebView) {
        currentURL = webView.url ?? currentURL
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        loadProgress = webView.estimatedProgress

        if !title.isEmpty {
            onTitleChange?(title)
        }
    }

    func handleLoadError(_ error: Error) {
        isLoading = false

        let nsError = error as NSError

        // Provide user-friendly error messages
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            if currentURL.host == "localhost" || currentURL.host == "127.0.0.1" {
                errorMessage = "Cannot connect to localhost:\(currentURL.port ?? 80). Is your dev server running?"
            } else {
                errorMessage = "Cannot connect to server"
            }
        case NSURLErrorNotConnectedToInternet:
            errorMessage = "No internet connection"
        case NSURLErrorTimedOut:
            errorMessage = "Connection timed out"
        case NSURLErrorCancelled:
            errorMessage = nil // User cancelled, not an error
        default:
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
