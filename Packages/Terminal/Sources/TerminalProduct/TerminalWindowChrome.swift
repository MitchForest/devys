import SwiftUI
import UI

#if os(macOS)
import AppKit

struct TerminalWindowChrome: NSViewRepresentable {
    var title: String
    var agentStatus: TerminalWindowAgentStatus?
    var theme: Theme
    var onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> TerminalWindowChromeView {
        TerminalWindowChromeView(
            title: title,
            agentStatus: agentStatus,
            theme: theme,
            onFocusChange: onFocusChange
        )
    }

    func updateNSView(_ nsView: TerminalWindowChromeView, context: Context) {
        nsView.title = title
        nsView.agentStatus = agentStatus
        nsView.theme = theme
        nsView.onFocusChange = onFocusChange
        nsView.configureWindowIfAvailable()
    }
}

final class TerminalWindowChromeView: NSView {
    var title: String
    var agentStatus: TerminalWindowAgentStatus?
    var theme: Theme
    var onFocusChange: (Bool) -> Void
    private var lastReportedFocus: Bool?
    private var statusAccessory: NSTitlebarAccessoryViewController?
    private var lastRenderedStatus: TerminalWindowAgentStatus?
    private weak var observedWindow: NSWindow?

    init(
        title: String,
        agentStatus: TerminalWindowAgentStatus?,
        theme: Theme,
        onFocusChange: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.agentStatus = agentStatus
        self.theme = theme
        self.onFocusChange = onFocusChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installFocusObservers()
        configureWindowIfAvailable()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configureWindowIfAvailable() {
        guard let window else { return }
        if window.title != title {
            window.title = title
        }
        configureAgentStatusAccessory(in: window)
        reportFocusIfChanged(window.isKeyWindow && NSApp.isActive)
    }

    private func configureAgentStatusAccessory(in window: NSWindow) {
        guard let agentStatus else {
            removeAgentStatusAccessory(from: window)
            return
        }

        if statusAccessory == nil {
            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .right
            statusAccessory = accessory
            window.addTitlebarAccessoryViewController(accessory)
        }

        guard let statusAccessory else { return }
        if lastRenderedStatus != agentStatus || statusAccessory.view.superview == nil {
            let hostingView = NSHostingView(rootView: agentStatusRootView(agentStatus))
            hostingView.frame.size = hostingView.fittingSize
            statusAccessory.view = hostingView
            lastRenderedStatus = agentStatus
        } else if let hostingView = statusAccessory.view as? NSHostingView<AnyView> {
            hostingView.rootView = agentStatusRootView(agentStatus)
            hostingView.frame.size = hostingView.fittingSize
        }
    }

    private func agentStatusRootView(_ agentStatus: TerminalWindowAgentStatus) -> AnyView {
        AnyView(
            TerminalWindowAgentStatusView(status: agentStatus)
                .environment(\.theme, theme)
        )
    }

    private func removeAgentStatusAccessory(from window: NSWindow) {
        guard let statusAccessory,
              let index = window.titlebarAccessoryViewControllers.firstIndex(of: statusAccessory)
        else { return }
        window.removeTitlebarAccessoryViewController(at: index)
        self.statusAccessory = nil
        lastRenderedStatus = nil
    }

    /// `configureWindowIfAvailable` runs from `updateNSView` (the SwiftUI render path).
    /// Forwarding focus changes synchronously would mutate `@Published` model state
    /// during view updates and trigger SwiftUI's "Publishing changes from within view
    /// updates is not allowed" runtime issue, which then spins forever as each focus
    /// callback invalidates the view that just ran it. We dedupe and dispatch to the
    /// next runloop tick to break the cycle.
    private func reportFocusIfChanged(_ isFocused: Bool) {
        guard lastReportedFocus != isFocused else { return }
        lastReportedFocus = isFocused
        let callback = onFocusChange
        DispatchQueue.main.async {
            callback(isFocused)
        }
    }

    private func installFocusObservers() {
        guard let window else { return }
        guard observedWindow !== window else { return }
        observedWindow = window
        let center = NotificationCenter.default
        center.removeObserver(self)
        center.addObserver(
            self,
            selector: #selector(windowFocusDidChange(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowFocusDidChange(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(applicationFocusDidChange(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationFocusDidChange(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func windowFocusDidChange(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        configureWindowIfAvailable()
    }

    @objc private func applicationFocusDidChange(_ notification: Notification) {
        _ = notification
        configureWindowIfAvailable()
    }
}
#else
struct TerminalWindowChrome: View {
    var title: String
    var agentStatus: TerminalWindowAgentStatus?
    var theme: Theme
    var onFocusChange: (Bool) -> Void

    var body: some View {
        EmptyView()
    }
}
#endif

private struct TerminalWindowAgentStatusView: View {
    @Environment(\.theme) private var theme
    @State private var isPulsing = false

    var status: TerminalWindowAgentStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .opacity(status.activity == .working && !isPulsing ? 0.45 : 1)

            Text(status.agentName)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            Text(statusLabel)
                .font(Typography.micro)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, Spacing.normal)
        .padding(.vertical, 4)
        .liquidGlassSurface(shape: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.agentName) \(statusLabel)")
        .onAppear {
            updatePulse()
        }
        .onChange(of: status.activity) { _, _ in
            updatePulse()
        }
    }

    private var statusLabel: String {
        switch status.activity {
        case .waiting:
            "waiting"
        case .working:
            "working"
        case .exited:
            "exited"
        case .error:
            "error"
        }
    }

    private var statusColor: Color {
        switch status.activity {
        case .waiting:
            theme.success
        case .working:
            theme.info
        case .exited:
            theme.textTertiary
        case .error:
            theme.error
        }
    }

    private func updatePulse() {
        guard status.activity == .working else {
            isPulsing = false
            return
        }
        isPulsing = false
        withAnimation(Animations.heartbeat) {
            isPulsing = true
        }
    }
}
