import Split
import SwiftUI
import UI
import Workspace

struct WorkspaceEmptyPaneView: View {
    @Environment(\.devysTheme) private var theme

    let paneID: PaneID
    let onFocusPane: (PaneID) -> Void
    let onOpenTerminal: (PaneID) -> Void
    let onOpenBrowser: (PaneID) -> Void
    let showsBrowser: Bool
    let canLaunchClaude: Bool
    let canLaunchCodex: Bool
    let onOpenClaude: (PaneID) -> Void
    let onOpenCodex: (PaneID) -> Void
    let onOpenAgent: (PaneID) -> Void
    let showsAgent: Bool
    let onOpenFile: (PaneID) -> Void
    let showsOpenFile: Bool

    @State private var isTerminalLauncherPickerPresented = false

    private enum LayoutMode {
        case regular
        case compact
        case minimal
    }

    private struct PaneAction: Identifiable {
        let id: String
        let title: String
        let icon: String
        let style: ActionButton.Style
        let isEnabled: Bool
        let perform: () -> Void
    }

    private var showsTerminalLauncherPicker: Bool {
        canLaunchClaude || canLaunchCodex
    }

    private var actions: [PaneAction] {
        [
            PaneAction(
                id: "terminal",
                title: "Terminal",
                icon: "terminal",
                style: .primary,
                isEnabled: true
            ) {
                onFocusPane(paneID)
                if showsTerminalLauncherPicker {
                    isTerminalLauncherPickerPresented = true
                } else {
                    onOpenTerminal(paneID)
                }
            },
            PaneAction(
                id: "browser",
                title: "Browser",
                icon: "globe",
                style: .ghost,
                isEnabled: showsBrowser
            ) {
                onFocusPane(paneID)
                onOpenBrowser(paneID)
            },
            PaneAction(
                id: "chat",
                title: "Chat",
                icon: "person.crop.circle.badge.plus",
                style: .ghost,
                isEnabled: showsAgent
            ) {
                onFocusPane(paneID)
                onOpenAgent(paneID)
            },
            PaneAction(
                id: "open-file",
                title: "Open File",
                icon: "doc",
                style: .ghost,
                isEnabled: showsOpenFile
            ) {
                onFocusPane(paneID)
                onOpenFile(paneID)
            }
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = layoutMode(for: geometry.size)

            VStack(spacing: layoutSpacing(for: layoutMode)) {
                watermark(for: layoutMode)
                actionsView(for: layoutMode)
            }
            .padding(containerPadding(for: layoutMode))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocusPane(paneID)
        }
        .sheet(isPresented: $isTerminalLauncherPickerPresented) {
            TerminalLauncherPickerSheet(
                canLaunchClaude: canLaunchClaude,
                canLaunchCodex: canLaunchCodex,
                onOpenShell: {
                    onOpenTerminal(paneID)
                },
                onOpenClaude: {
                    onOpenClaude(paneID)
                },
                onOpenCodex: {
                    onOpenCodex(paneID)
                }
            )
        }
    }

    @ViewBuilder
    private func watermark(for layoutMode: LayoutMode) -> some View {
        VStack(spacing: layoutMode == .minimal ? Spacing.space2 : Spacing.space3) {
            DevysLogo(size: .small)
                .opacity(layoutMode == .minimal ? 0.42 : 0.55)

            if layoutMode != .minimal {
                Text("› choose a surface for this pane")
                    .font(Typography.Code.sm)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionsView(for layoutMode: LayoutMode) -> some View {
        switch layoutMode {
        case .regular:
            HStack(spacing: Spacing.space2) {
                ForEach(actions) { action in
                    labeledActionButton(for: action)
                }
            }

        case .compact:
            VStack(spacing: Spacing.space2) {
                HStack(spacing: Spacing.space2) {
                    ForEach(actions.prefix(2)) { action in
                        labeledActionButton(for: action)
                    }
                }

                HStack(spacing: Spacing.space2) {
                    ForEach(actions.suffix(from: 2)) { action in
                        labeledActionButton(for: action)
                    }
                }
            }

        case .minimal:
            Grid(horizontalSpacing: Spacing.space2, verticalSpacing: Spacing.space2) {
                GridRow {
                    iconActionButton(for: actions[0])
                    iconActionButton(for: actions[1])
                }

                GridRow {
                    iconActionButton(for: actions[2])
                    iconActionButton(for: actions[3])
                }
            }
        }
    }

    private func labeledActionButton(for action: PaneAction) -> some View {
        ActionButton(action.title, icon: action.icon, style: action.style) {
            action.perform()
        }
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.45)
    }

    private func iconActionButton(for action: PaneAction) -> some View {
        IconButton(
            action.icon,
            style: action.style,
            size: .lg,
            accessibilityLabel: action.title
        ) {
            action.perform()
        }
        .disabled(!action.isEnabled)
        .opacity(action.isEnabled ? 1 : 0.45)
        .help(action.title)
    }

    private func layoutMode(for size: CGSize) -> LayoutMode {
        if size.width < 240 || size.height < 190 {
            return .minimal
        }
        if size.width < 360 || size.height < 250 {
            return .compact
        }
        return .regular
    }

    private func layoutSpacing(for layoutMode: LayoutMode) -> CGFloat {
        switch layoutMode {
        case .regular:
            return Spacing.space5
        case .compact:
            return Spacing.space4
        case .minimal:
            return Spacing.space2
        }
    }

    private func containerPadding(for layoutMode: LayoutMode) -> CGFloat {
        switch layoutMode {
        case .regular:
            return Spacing.space5
        case .compact:
            return Spacing.space4
        case .minimal:
            return Spacing.space2
        }
    }

}

private struct TerminalLauncherPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme
    @Environment(AppSettings.self) private var appSettings

    let canLaunchClaude: Bool
    let canLaunchCodex: Bool
    let onOpenShell: () -> Void
    let onOpenClaude: () -> Void
    let onOpenCodex: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space4) {
            Text("Open Terminal")
                .font(Typography.title)
                .foregroundStyle(theme.text)

            Text("Choose a plain shell or launch a configured agent terminal for this workspace.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: Spacing.space3) {
                launcherButton(
                    title: "Shell",
                    subtitle: "Open a plain shell",
                    icon: "terminal",
                    shortcut: appSettings.shortcuts.binding(for: .launchShell).displayString,
                    action: onOpenShell
                )

                if canLaunchClaude {
                    launcherButton(
                        title: "Claude Code",
                        subtitle: "Use repository launcher settings",
                        icon: DevysIconName.claudeCode,
                        shortcut: appSettings.shortcuts.binding(for: .launchClaude).displayString,
                        action: onOpenClaude
                    )
                }

                if canLaunchCodex {
                    launcherButton(
                        title: "Codex",
                        subtitle: "Use repository launcher settings",
                        icon: DevysIconName.codex,
                        shortcut: appSettings.shortcuts.binding(for: .launchCodex).displayString,
                        action: onOpenCodex
                    )
                }
            }

            HStack {
                Spacer()
                ActionButton("Cancel", style: .ghost) {
                    dismiss()
                }
            }
        }
        .padding(Spacing.space5)
        .frame(width: 560)
        .elevation(.overlay)
    }

    private func launcherButton(
        title: String,
        subtitle: String,
        icon: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                HStack(alignment: .top) {
                    DevysIcon(icon, size: 18)
                        .foregroundStyle(theme.accent)
                    Spacer()
                    if !shortcut.isEmpty {
                        ShortcutBadge(shortcut)
                    }
                }

                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)

                Text(subtitle)
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(Spacing.space4)
            .elevation(.card)
        }
        .buttonStyle(.plain)
    }
}
