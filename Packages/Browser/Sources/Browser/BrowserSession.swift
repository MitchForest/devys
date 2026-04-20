// BrowserSession.swift
// DevysBrowser - Browser integration for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
@preconcurrency import WebKit

/// A browser session that owns a WKWebView and tracks its state.
///
/// Sessions are independent of tabs - each browser tab has its own session
/// that manages the WKWebView lifecycle.
@MainActor
@Observable
public final class BrowserSession: Identifiable {

    // MARK: - Identity

    public let id: UUID

    // MARK: - State

    /// Current URL
    public private(set) var url: URL

    /// Page title
    private(set) var title: String = ""

    /// Whether the page is loading
    private(set) var isLoading: Bool = false

    /// Load progress (0.0 to 1.0)
    private(set) var loadProgress: Double = 0

    /// Whether browser can navigate back
    private(set) var canGoBack: Bool = false

    /// Whether browser can navigate forward
    private(set) var canGoForward: Bool = false

    /// Error message if load failed
    private(set) var errorMessage: String?

    // MARK: - Tab Metadata

    /// Title for display in tab bar
    public var tabTitle: String {
        if title.isEmpty {
            return url.host ?? "Browser"
        }
        return title
    }

    /// Icon for display in tab bar
    public var tabIcon: String { "globe" }

    // MARK: - WebView

    /// The WKWebView for this session (created lazily)
    private var webView: WKWebView?

    /// KVO observations
    private var observations: [NSKeyValueObservation] = []

    /// Prevent stale callbacks from touching state during teardown.
    private var isClosing = false

    // MARK: - Initialization

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    // MARK: - WebView Lifecycle

    /// Creates and configures the WKWebView if not already created.
    /// Call this when the session is about to be displayed.
    func ensureWebView() -> WKWebView {
        if let existing = webView {
            return existing
        }

        isClosing = false

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true

        setupObservers(for: view)
        webView = view

        // Load initial URL
        view.load(URLRequest(url: url))

        return view
    }

    private func setupObservers(for webView: WKWebView) {
        observations = [
            webView.observe(\.url) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.syncState(from: webView)
                }
            },
            webView.observe(\.title) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.syncState(from: webView)
                }
            },
            webView.observe(\.canGoBack) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isManaging(webView) else { return }
                    self.canGoBack = webView.canGoBack
                }
            },
            webView.observe(\.canGoForward) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isManaging(webView) else { return }
                    self.canGoForward = webView.canGoForward
                }
            },
            webView.observe(\.isLoading) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isManaging(webView) else { return }
                    self.isLoading = webView.isLoading
                }
            },
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isManaging(webView) else { return }
                    self.loadProgress = webView.estimatedProgress
                }
            }
        ]
    }

    private func syncState(from webView: WKWebView) {
        guard isManaging(webView) else { return }

        if let newURL = webView.url, newURL != url {
            url = newURL
        }

        let newTitle = webView.title ?? ""
        if newTitle != title {
            title = newTitle
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        loadProgress = webView.estimatedProgress
    }

    // MARK: - Navigation

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        clearError()
        webView?.reload()
    }

    func stopLoading() {
        webView?.stopLoading()
    }

    public func load(url: URL) {
        self.url = url
        clearError()
        webView?.load(URLRequest(url: url))
    }

    func load(urlString: String) {
        guard let url = normalizeURLString(urlString) else {
            errorMessage = "Invalid URL"
            return
        }
        load(url: url)
    }

    // MARK: - Error Handling

    func handleLoadError(_ error: Error) {
        isLoading = false

        let nsError = error as NSError

        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            if url.host == "localhost" || url.host == "127.0.0.1" {
                errorMessage = "Cannot connect to localhost:\(url.port ?? 80). Is your dev server running?"
            } else {
                errorMessage = "Cannot connect to server"
            }
        case NSURLErrorNotConnectedToInternet:
            errorMessage = "No internet connection"
        case NSURLErrorTimedOut:
            errorMessage = "Connection timed out"
        case NSURLErrorCancelled:
            errorMessage = nil
        default:
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Teardown

    func setNavigationDelegate(_ delegate: WKNavigationDelegate?) {
        webView?.navigationDelegate = delegate
    }

    public func beginRemoval() {
        guard !isClosing else { return }
        isClosing = true
        webView?.stopLoading()
        isLoading = false
        loadProgress = 0
    }

    func dismantleHostedWebView(_ hostedWebView: WKWebView) {
        hostedWebView.stopLoading()
        hostedWebView.navigationDelegate = nil
        hostedWebView.uiDelegate = nil

        guard webView === hostedWebView else { return }

        invalidateObservations()
        webView = nil
        canGoBack = false
        canGoForward = false
        isLoading = false
        loadProgress = 0
    }

    func isManaging(_ webView: WKWebView) -> Bool {
        self.webView === webView && !isClosing
    }

    private func invalidateObservations() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
    }

    // MARK: - URL Normalization

    private func normalizeURLString(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Already a valid URL
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        // Add https:// prefix
        if let url = URL(string: "https://\(trimmed)") {
            return url
        }

        return nil
    }
}
