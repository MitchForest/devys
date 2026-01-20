import SwiftUI
import WebKit

/// SwiftUI wrapper for WKWebView.
public struct BrowserWebView: NSViewRepresentable {
    let store: WebViewStore
    let initialURL: URL

    public init(store: WebViewStore, initialURL: URL) {
        self.store = store
        self.initialURL = initialURL
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Enable developer extras (Inspect Element)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Allow JavaScript
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Store reference
        Task { @MainActor in
            store.webView = webView
        }

        // Set up KVO observers
        context.coordinator.setupObservers(for: webView)

        // Load initial URL
        webView.load(URLRequest(url: initialURL))

        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        // State updates handled via KVO and delegate
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, WKNavigationDelegate {
        let store: WebViewStore
        private var observations: [NSKeyValueObservation] = []

        init(store: WebViewStore) {
            self.store = store
        }

        deinit {
            observations.removeAll()
        }

        func setupObservers(for webView: WKWebView) {
            observations = [
                webView.observe(\.url) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.title) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.canGoBack) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.canGoForward) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.isLoading) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.updateNavigationState(from: webView)
                    }
                },
                webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                    Task { @MainActor in
                        self?.store.loadProgress = webView.estimatedProgress
                    }
                }
            ]
        }

        // MARK: - WKNavigationDelegate

        public func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            Task { @MainActor in
                store.isLoading = true
                store.clearError()
            }
        }

        public func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            Task { @MainActor in
                store.isLoading = false
                store.updateNavigationState(from: webView)
            }
        }

        public func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                store.handleLoadError(error)
            }
        }

        public func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                store.handleLoadError(error)
            }
        }
    }
}
