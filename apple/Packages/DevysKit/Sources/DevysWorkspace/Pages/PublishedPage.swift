import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI
import WebKit

/// The policy pages render under, the web's `pagePolicy` (src/artifacts/contract.ts): inline
/// styles, scripts and data: images; nothing fetched, no forms, no navigation.
private let pagePolicy =
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

/// A published page over the workspace: dashed until it is kept in a space.
struct PublishedPageSheet: View {
    let store: StoreOf<Workspace>
    let artifactID: String
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.runtimeClient) private var runtime
    @State private var spaceID = ""
    @State private var saving = false
    @State private var problem: String?

    private var spaces: [Space] { store.spaces.value ?? [] }
    private var keptIn: [Space] { spaces.filter { $0.refs(.artifact).contains(artifactID) } }
    private var title: String {
        store.state.artifacts.first { $0.id == artifactID }?.filename.replacingOccurrences(of: ".html", with: "") ?? "Page"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(DevysTypography.heading).foregroundStyle(DevysColors.ink).lineLimit(1)
                if keptIn.isEmpty {
                    DashedTag("Not kept")
                } else {
                    Text("In \(keptIn.map(\.name).joined(separator: ", "))").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                Spacer(minLength: 8)
                if !spaces.isEmpty {
                    Picker("Space", selection: $spaceID) {
                        ForEach(spaces) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button(saving ? "Saving…" : "Save to space") { Task { await save() } }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        .disabled(saving || spaceID.isEmpty)
                }
                ToolbarIconButton("Close", symbol: "xmark") { dismiss() }
            }
            .padding(12)
            if let problem { Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2).padding(.bottom, 8) }
            Divider()
            PublishedPage(businessID: store.businessID, artifactID: artifactID)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { spaceID = spaces.first?.id ?? "" }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await runtime.addToSpace(store.businessID, spaceID, .artifact, artifactID)
            problem = nil
            store.send(.refreshTapped)
        } catch {
            problem = "It wasn't saved. \(error.localizedDescription)"
        }
    }
}
