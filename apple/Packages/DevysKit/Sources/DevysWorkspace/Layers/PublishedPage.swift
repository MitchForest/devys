import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI
import WebKit

/// The policy pages render under, the web's `pagePolicy` (src/apps/documents/contract.ts): inline
/// styles, scripts and data: images; nothing fetched, no forms, no navigation.
let pagePolicy =
    "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'"

/// An employee's HTML page in its own web view: no stored data, the policy first, and no
/// navigation away (links do nothing).
struct SandboxedPage {
    let html: String

    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = Guard.shared
        view.loadHTMLString(
            "<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"\(pagePolicy)\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\(html)",
            baseURL: nil
        )
        return view
    }

    /// Allows the page's own load and nothing else.
    final class Guard: NSObject, WKNavigationDelegate {
        static let shared = Guard()

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other && (action.request.url?.absoluteString ?? "about:blank").hasPrefix("about:") ? .allow : .cancel
        }
    }
}

#if os(macOS)
extension SandboxedPage: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
extension SandboxedPage: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

/// A page an employee published, loaded from the business.
struct PublishedPage: View {
    let businessID: String
    let artifactID: String
    @Dependency(\.runtimeClient) private var runtime
    @State private var html: String?
    @State private var problem: String?

    var body: some View {
        Group {
            if let html {
                SandboxedPage(html: html)
            } else if let problem {
                EmptyNote(text: problem).padding(14)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: artifactID) {
            do {
                html = try await runtime.artifactText(businessID, artifactID)
            } catch {
                problem = "This page couldn't be opened. \(error.localizedDescription)"
            }
        }
    }
}
