// BrowserContentView.swift
// DevysBrowser - Browser integration for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import WebKit
import UI

/// Browser content view that displays a web page with navigation controls.
@MainActor
public struct BrowserContentView: View {
    let session: BrowserSession

    @Environment(\.devysTheme) private var theme
    @State private var urlText: String = ""
    @FocusState private var isURLFieldFocused: Bool

    public init(session: BrowserSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack {
                BrowserWebViewWrapper(session: session)

                if let error = session.errorMessage {
                    errorOverlay(message: error)
                }
            }
        }
        .onAppear {
            urlText = session.url.absoluteString
        }
        .onChange(of: session.url) { _, newURL in
            if !isURLFieldFocused {
                urlText = newURL.absoluteString
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Back button
                Button(action: { session.goBack() }, label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                })
                .buttonStyle(.plain)
                .disabled(!session.canGoBack)
                .opacity(session.canGoBack ? 1 : 0.4)
                .help("Go Back")

                // Forward button
                Button(action: { session.goForward() }, label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                })
                .buttonStyle(.plain)
                .disabled(!session.canGoForward)
                .opacity(session.canGoForward ? 1 : 0.4)
                .help("Go Forward")

                // Reload/Stop button
                Button(action: {
                    if session.isLoading {
                        session.stopLoading()
                    } else {
                        session.reload()
                    }
                }, label: {
                    Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                })
                .buttonStyle(.plain)
                .help(session.isLoading ? "Stop Loading" : "Reload")

                // URL field
                TextField("Enter URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        session.load(urlString: urlText)
                        isURLFieldFocused = false
                    }
                    .onChange(of: isURLFieldFocused) { _, focused in
                        if focused {
                            urlText = session.url.absoluteString
                        }
                    }

                // Localhost quick access
                Menu {
                    ForEach(CommonPorts.all, id: \.port) { item in
                        Button("\(item.name) (:\(item.port))") {
                            if let url = URL(string: "http://localhost:\(item.port)") {
                                session.load(url: url)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "network")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Localhost Ports")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Progress bar
            if session.isLoading {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(theme.accent.opacity(0.6))
                        .frame(width: geometry.size.width * session.loadProgress)
                        .animation(.easeInOut(duration: 0.2), value: session.loadProgress)
                }
                .frame(height: 2)
            } else {
                Color.clear.frame(height: 2)
            }
        }
        .background(theme.card)
    }

    // MARK: - Error Overlay

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                session.clearError()
                session.reload()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }
}

// MARK: - WebView Wrapper

/// NSViewRepresentable wrapper for WKWebView.
@MainActor
private struct BrowserWebViewWrapper: NSViewRepresentable {
    let session: BrowserSession

    func makeNSView(context: Context) -> WKWebView {
        let webView = session.ensureWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // State updates handled via KVO in BrowserSession
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let session: BrowserSession

        init(session: BrowserSession) {
            self.session = session
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation?
        ) {
            MainActor.assumeIsolated {
                session.clearError()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            MainActor.assumeIsolated {
                session.handleLoadError(error)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            MainActor.assumeIsolated {
                session.handleLoadError(error)
            }
        }
    }
}

// MARK: - Common Ports

private enum CommonPorts {
    struct Port {
        let name: String
        let port: Int
    }

    static let all: [Port] = [
        Port(name: "Vite", port: 5173),
        Port(name: "Next.js", port: 3000),
        Port(name: "Create React App", port: 3000),
        Port(name: "Vue CLI", port: 8080),
        Port(name: "Angular", port: 4200),
        Port(name: "Remix", port: 3000),
        Port(name: "Astro", port: 4321),
        Port(name: "SvelteKit", port: 5173),
        Port(name: "Webpack Dev Server", port: 8080),
        Port(name: "Rails", port: 3000),
        Port(name: "Django", port: 8000),
        Port(name: "Flask", port: 5000),
        Port(name: "Express", port: 3000),
        Port(name: "Phoenix", port: 4000)
    ]
}
