// BrowserContentView.swift
// DevysBrowser - Browser integration for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI
@preconcurrency import WebKit

/// A localhost port surfaced in the browser's port menu.
///
/// `BrowserContentView` does not detect ports itself — the host injects a
/// `BrowserPortProvider` so that detection policy stays out of the package.
public struct BrowserDetectedPort: Identifiable, Hashable, Sendable {
    public let port: Int
    public let processName: String

    public init(port: Int, processName: String) {
        self.port = port
        self.processName = processName
    }

    public var id: String { "\(port)-\(processName)" }
}

/// Closure that returns currently-listening localhost ports for the active project.
public typealias BrowserPortProvider = @Sendable () async -> [BrowserDetectedPort]

/// A host-owned localhost quick action rendered by the browser toolbar.
public struct BrowserLocalhostAction: Identifiable, Hashable, Sendable {
    public let port: Int
    public let label: String

    public init(port: Int, label: String) {
        self.port = port
        self.label = label
    }

    public var id: Int { port }
}

/// Browser content view that displays a web page with navigation controls.
@MainActor
public struct BrowserContentView: View {
    let session: BrowserSession
    let portProvider: BrowserPortProvider?
    let localhostActions: [BrowserLocalhostAction]

    @Environment(\.theme) private var theme
    @State private var urlText: String = ""
    @State private var detectedPorts: [BrowserDetectedPort] = []
    @State private var isURLFieldHovered = false
    @FocusState private var isURLFieldFocused: Bool

    public init(
        session: BrowserSession,
        portProvider: BrowserPortProvider? = nil,
        localhostActions: [BrowserLocalhostAction] = []
    ) {
        self.session = session
        self.portProvider = portProvider
        self.localhostActions = localhostActions
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
            Task { await refreshDetectedPorts() }
        }
        .task {
            await refreshDetectedPorts()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.normal) {
                navButton(
                    systemName: "chevron.left",
                    enabled: session.canGoBack,
                    help: "Go Back",
                    action: { session.goBack() }
                )

                navButton(
                    systemName: "chevron.right",
                    enabled: session.canGoForward,
                    help: "Go Forward",
                    action: { session.goForward() }
                )

                navButton(
                    systemName: session.isLoading ? "xmark" : "arrow.clockwise",
                    enabled: true,
                    help: session.isLoading ? "Stop Loading" : "Reload",
                    action: {
                        if session.isLoading {
                            session.stopLoading()
                        } else {
                            session.reload()
                        }
                    }
                )

                urlField

                portsMenu
            }
            .padding(.horizontal, Spacing.normal)
            .padding(.vertical, Spacing.paneGap)

            // Loading progress indicator (always-present 2pt slot to avoid layout shift).
            ZStack(alignment: .leading) {
                Color.clear
                if session.isLoading {
                    GeometryReader { geometry in
                        Capsule(style: .continuous)
                            .fill(theme.accent.opacity(0.6))
                            .frame(width: geometry.size.width * session.loadProgress)
                            .animation(Animations.micro, value: session.loadProgress)
                    }
                }
            }
            .frame(height: 2)
        }
        .background(theme.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: Spacing.borderWidth)
        }
    }

    // MARK: - URL Field

    private var urlField: some View {
        HStack(spacing: Spacing.tight) {
            Image(systemName: urlIconName)
                .font(Typography.caption.weight(.medium))
                .foregroundStyle(theme.textTertiary)

            TextField("Enter URL", text: $urlText)
                .textFieldStyle(.plain)
                .font(Typography.Code.sm)
                .foregroundStyle(theme.text)
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
        }
        .padding(.horizontal, Spacing.normal)
        .padding(.vertical, Spacing.tight)
        .background(
            urlFieldBackground,
            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .strokeBorder(urlFieldBorder, lineWidth: Spacing.borderWidth)
        )
        .onHover { isURLFieldHovered = $0 }
    }

    private var urlFieldBackground: Color {
        if isURLFieldFocused { return theme.card }
        return isURLFieldHovered ? theme.hover : theme.card
    }

    private var urlFieldBorder: Color {
        isURLFieldFocused ? theme.borderFocus : theme.border
    }

    private var urlIconName: String {
        guard let scheme = session.url.scheme?.lowercased() else { return "globe" }
        switch scheme {
        case "http", "https":
            return session.url.host == "localhost" ? "network" : "globe"
        case "file":
            return "doc"
        default:
            return "globe"
        }
    }

    // MARK: - Nav Buttons

    private func navButton(
        systemName: String,
        enabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Typography.caption.weight(.medium))
                .frame(width: Spacing.iconLg, height: Spacing.iconLg)
                .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary)
                .contentShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    // MARK: - Ports Menu

    private var portsMenu: some View {
        Menu {
            if !detectedPorts.isEmpty {
                Section("Detected") {
                    ForEach(detectedPorts) { port in
                        Button(detectedPortLabel(port)) {
                            loadLocalhost(port: port.port)
                        }
                    }
                }
            }
            if !localhostActions.isEmpty {
                Section("Localhost") {
                    ForEach(localhostActions) { action in
                        Button("\(action.label) - :\(action.port)") {
                            loadLocalhost(port: action.port)
                        }
                    }
                }
            }
            Divider()
            Button("Refresh") {
                Task { await refreshDetectedPorts() }
            }
        } label: {
            Image(systemName: "network")
                .font(Typography.caption.weight(.medium))
                .frame(width: Spacing.iconLg, height: Spacing.iconLg)
                .foregroundStyle(detectedPorts.isEmpty ? theme.textSecondary : theme.accent)
        }
        .menuStyle(.borderlessButton)
        .frame(width: Spacing.iconLg)
        .help(detectedPorts.isEmpty
              ? "Localhost ports"
              : "\(detectedPorts.count) detected localhost port\(detectedPorts.count == 1 ? "" : "s")")
    }

    private func detectedPortLabel(_ port: BrowserDetectedPort) -> String {
        "localhost:\(port.port) — \(port.processName)"
    }

    private func loadLocalhost(port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        session.load(url: url)
    }

    private func refreshDetectedPorts() async {
        guard let portProvider else { return }
        let ports = await portProvider()
        await MainActor.run {
            detectedPorts = ports
        }
    }

    // MARK: - Error Overlay

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: Spacing.relaxed) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: Spacing.iconXl * 2))
                .foregroundStyle(theme.textTertiary)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.relaxed)

            ActionButton("Retry", style: .ghost) {
                session.clearError()
                session.reload()
            }
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
        session.setNavigationDelegate(context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        session.setNavigationDelegate(context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.session.dismantleHostedWebView(nsView)
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
            Task { @MainActor [session] in
                guard session.isManaging(webView) else { return }
                session.clearError()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            Task { @MainActor [session] in
                guard session.isManaging(webView) else { return }
                session.handleLoadError(error)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            Task { @MainActor [session] in
                guard session.isManaging(webView) else { return }
                session.handleLoadError(error)
            }
        }
    }
}
