// TitlebarToolbar.swift
// Devys - Native macOS titlebar toolbar host for workspace launch actions.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI

struct WindowTitlebarToolbarHost: NSViewRepresentable {
    let theme: DevysTheme
    let hasRepositories: Bool
    let hasWorktree: Bool
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void
    let onAgents: () -> Void
    let onShell: () -> Void
    let onClaude: () -> Void
    let onCodex: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration)
    }

    func makeNSView(context: Context) -> WindowObservationView {
        let view = WindowObservationView()
        view.onWindowAvailable = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObservationView, context: Context) {
        nsView.onWindowAvailable = { window in
            context.coordinator.attach(to: window)
        }
        context.coordinator.update(configuration)
        if let window = nsView.window {
            context.coordinator.attach(to: window)
        }
    }

    private var configuration: Coordinator.Configuration {
        .init(
            theme: theme,
            hasRepositories: hasRepositories,
            hasWorktree: hasWorktree,
            isSidebarVisible: isSidebarVisible,
            onToggleSidebar: onToggleSidebar,
            onAgents: onAgents,
            onShell: onShell,
            onClaude: onClaude,
            onCodex: onCodex
        )
    }
}

final class WindowObservationView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowAvailable?(window)
        }
    }
}

@MainActor
final class Coordinator: NSObject, NSToolbarDelegate {
    struct Configuration {
        let theme: DevysTheme
        let hasRepositories: Bool
        let hasWorktree: Bool
        let isSidebarVisible: Bool
        let onToggleSidebar: () -> Void
        let onAgents: () -> Void
        let onShell: () -> Void
        let onClaude: () -> Void
        let onCodex: () -> Void
    }

    private enum Identifiers {
        static let toolbar = NSToolbar.Identifier("com.devys.window.titlebar-toolbar")
        static let sidebar = NSToolbarItem.Identifier("com.devys.window.sidebar")
        static let launchers = NSToolbarItem.Identifier("com.devys.window.launchers")
    }

    private let toolbar = NSToolbar(identifier: Identifiers.toolbar)
    private let sidebarItem = NSToolbarItem(itemIdentifier: Identifiers.sidebar)
    private let launchersItem = NSToolbarItem(itemIdentifier: Identifiers.launchers)
    private let sidebarHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let launchersHostingView = NSHostingView(rootView: AnyView(EmptyView()))

    private weak var window: NSWindow?
    private var configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init()

        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .default
        toolbar.sizeMode = .small
        toolbar.showsBaselineSeparator = false

        sidebarHostingView.sizingOptions = [.intrinsicContentSize]
        launchersHostingView.sizingOptions = [.intrinsicContentSize]

        sidebarItem.view = sidebarHostingView
        launchersItem.view = launchersHostingView
        sidebarItem.label = "Sidebar"
        launchersItem.label = "Launchers"
    }

    func attach(to window: NSWindow) {
        if self.window !== window || window.toolbar?.identifier != Identifiers.toolbar {
            self.window = window
            window.toolbar = toolbar
            window.titleVisibility = .hidden
            window.toolbarStyle = .unifiedCompact
        }
        refreshViews()
    }

    func update(_ configuration: Configuration) {
        self.configuration = configuration
        refreshViews()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Identifiers.sidebar, .flexibleSpace, Identifiers.launchers]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Identifiers.sidebar, .flexibleSpace, Identifiers.launchers]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Identifiers.sidebar:
            return sidebarItem
        case Identifiers.launchers:
            return launchersItem
        default:
            return nil
        }
    }

    private func refreshViews() {
        apply(
            rootView: AnyView(sidebarRootView),
            to: sidebarHostingView,
            item: sidebarItem
        )
        apply(
            rootView: AnyView(launchersRootView),
            to: launchersHostingView,
            item: launchersItem
        )
    }

    private var sidebarRootView: some View {
        Group {
            if configuration.hasRepositories {
                SidebarToolbarButton(
                    isSidebarVisible: configuration.isSidebarVisible,
                    action: configuration.onToggleSidebar
                )
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .environment(\.devysTheme, configuration.theme)
    }

    private var launchersRootView: some View {
        Group {
            if configuration.hasRepositories {
                TitlebarActionButtons(
                    hasWorktree: configuration.hasWorktree,
                    onAgents: configuration.onAgents,
                    onShell: configuration.onShell,
                    onClaude: configuration.onClaude,
                    onCodex: configuration.onCodex
                )
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .environment(\.devysTheme, configuration.theme)
    }

    private func apply(
        rootView: AnyView,
        to hostingView: NSHostingView<AnyView>,
        item: NSToolbarItem
    ) {
        hostingView.rootView = rootView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.invalidateIntrinsicContentSize()

        let size = hostingView.fittingSize
        item.minSize = size
        item.maxSize = size
    }
}

private struct SidebarToolbarButton: View {
    @Environment(\.devysTheme) private var theme

    let isSidebarVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSidebarVisible ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? "Hide Sidebar (⌘\\)" : "Show Sidebar (⌘\\)")
    }
}

private struct TitlebarActionButtons: View {
    @Environment(\.devysTheme) private var theme

    let hasWorktree: Bool
    let onAgents: () -> Void
    let onShell: () -> Void
    let onClaude: () -> Void
    let onCodex: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            titlebarButton("Shell", icon: "terminal", enabled: hasWorktree, action: onShell)
            titlebarButton("Agents", icon: "message.badge.waveform", enabled: hasWorktree, action: onAgents)
            titlebarButton(
                "Codex",
                icon: "chevron.left.forwardslash.chevron.right",
                enabled: hasWorktree,
                action: onCodex
            )
            titlebarButton("Claude", icon: "brain", enabled: hasWorktree, action: onClaude)
        }
        .fixedSize()
    }

    private func titlebarButton(
        _ title: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(enabled ? theme.elevated : theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        enabled ? theme.border : theme.borderSubtle,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? title : "Open a workspace to enable \(title)")
    }
}
