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
    let repoName: String?
    let branchName: String?
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
            repoName: repoName,
            branchName: branchName,
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
        let repoName: String?
        let branchName: String?
        let onToggleSidebar: () -> Void
        let onAgents: () -> Void
        let onShell: () -> Void
        let onClaude: () -> Void
        let onCodex: () -> Void
    }

    private enum Identifiers {
        static let toolbar = NSToolbar.Identifier("com.devys.window.titlebar-toolbar")
        static let sidebar = NSToolbarItem.Identifier("com.devys.window.sidebar")
        static let breadcrumb = NSToolbarItem.Identifier("com.devys.window.breadcrumb")
        static let launchers = NSToolbarItem.Identifier("com.devys.window.launchers")
    }

    private let toolbar = NSToolbar(identifier: Identifiers.toolbar)
    private let sidebarItem = NSToolbarItem(itemIdentifier: Identifiers.sidebar)
    private let breadcrumbItem = NSToolbarItem(itemIdentifier: Identifiers.breadcrumb)
    private let launchersItem = NSToolbarItem(itemIdentifier: Identifiers.launchers)
    private let sidebarHostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let breadcrumbHostingView = NSHostingView(rootView: AnyView(EmptyView()))
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
        breadcrumbHostingView.sizingOptions = [.intrinsicContentSize]
        launchersHostingView.sizingOptions = [.intrinsicContentSize]

        sidebarItem.view = sidebarHostingView
        breadcrumbItem.view = breadcrumbHostingView
        launchersItem.view = launchersHostingView
        sidebarItem.label = "Sidebar"
        breadcrumbItem.label = "Location"
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
        [Identifiers.sidebar, .flexibleSpace, Identifiers.breadcrumb, .flexibleSpace, Identifiers.launchers]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Identifiers.sidebar, .flexibleSpace, Identifiers.breadcrumb, .flexibleSpace, Identifiers.launchers]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Identifiers.sidebar:
            return sidebarItem
        case Identifiers.breadcrumb:
            return breadcrumbItem
        case Identifiers.launchers:
            return launchersItem
        default:
            return nil
        }
    }

    private func refreshViews() {
        apply(
            rootView: AnyView(sidebarRootView),
            to: sidebarHostingView
        )
        apply(
            rootView: AnyView(breadcrumbRootView),
            to: breadcrumbHostingView
        )
        apply(
            rootView: AnyView(launchersRootView),
            to: launchersHostingView
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

    private var breadcrumbRootView: some View {
        Group {
            if let repoName = configuration.repoName {
                TitlebarBreadcrumb(
                    repoName: repoName,
                    branchName: configuration.branchName
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
                TitlebarFABButton(
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
        to hostingView: NSHostingView<AnyView>
    ) {
        hostingView.rootView = rootView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.invalidateIntrinsicContentSize()
        hostingView.setFrameSize(hostingView.fittingSize)
    }
}

private struct SidebarToolbarButton: View {
    @Environment(\.devysTheme) private var theme

    let isSidebarVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSidebarVisible ? "sidebar.right" : "sidebar.left")
                .font(Typography.label)
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? "Hide Sidebar (⌘\\)" : "Show Sidebar (⌘\\)")
    }
}

/// Single (+) FAB button that opens a popover menu with launch actions.
///
/// Replaces the four separate titlebar buttons (Shell, Agents, Codex, Claude)
/// with one clean creation entry point.
private struct TitlebarFABButton: View {
    @Environment(\.devysTheme) private var theme

    let hasWorktree: Bool
    let onAgents: () -> Void
    let onShell: () -> Void
    let onClaude: () -> Void
    let onCodex: () -> Void

    @State private var showMenu = false
    @State private var isHovered = false

    var body: some View {
        Button {
            showMenu.toggle()
        } label: {
            Image(systemName: "plus")
                .font(Typography.label.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(theme.accent, in: Circle())
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
        .help("New tab (⌘T)")
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            fabMenuContent
                .environment(\.devysTheme, theme)
        }
    }

    private var fabMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            fabMenuItem(
                "Terminal",
                icon: "terminal",
                shortcut: "⌘T",
                enabled: hasWorktree,
                action: onShell
            )
            fabMenuItem(
                "Agent Session",
                icon: "sparkles",
                shortcut: "⌘⇧A",
                enabled: hasWorktree,
                action: onAgents
            )
            fabMenuItem(
                "Claude Code",
                icon: "brain",
                shortcut: "⌘⇧C",
                enabled: hasWorktree,
                action: onClaude
            )
            fabMenuItem(
                "Codex",
                icon: "chevron.left.forwardslash.chevron.right",
                shortcut: "⌘⇧X",
                enabled: hasWorktree,
                action: onCodex
            )
        }
        .padding(.vertical, Spacing.space1)
        .frame(width: 220)
        .elevation(.popover)
    }

    private func fabMenuItem(
        _ title: String,
        icon: String,
        shortcut: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            showMenu = false
            action()
        } label: {
            HStack(spacing: Spacing.space2) {
                Image(systemName: icon)
                    .font(Typography.body)
                    .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary)
                    .frame(width: 18)

                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(enabled ? theme.text : theme.textTertiary)

                Spacer()

                ShortcutBadge(shortcut)
                    .opacity(enabled ? 1 : 0.7)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Centered titlebar breadcrumb showing the current repo and branch.
private struct TitlebarBreadcrumb: View {
    @Environment(\.devysTheme) private var theme

    let repoName: String
    let branchName: String?

    var body: some View {
        HStack(spacing: Spacing.space1) {
            Text(repoName)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            if let branchName {
                Image(systemName: "chevron.right")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(theme.textTertiary)

                Image(systemName: "arrow.triangle.branch")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)

                Text(branchName)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .lineLimit(1)
    }
}
