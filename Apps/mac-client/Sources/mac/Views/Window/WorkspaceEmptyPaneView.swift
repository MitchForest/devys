import Split
import SwiftUI
import UI

struct WorkspaceEmptyPaneView: View {
    @Environment(\.devysTheme) private var theme

    let paneID: PaneID
    let onFocusPane: (PaneID) -> Void
    let onOpenTerminal: (PaneID) -> Void
    let onOpenBrowser: (PaneID) -> Void
    let canLaunchClaude: Bool
    let canLaunchCodex: Bool
    let onOpenClaude: (PaneID) -> Void
    let onOpenCodex: (PaneID) -> Void
    let onOpenAgent: (PaneID) -> Void
    let onOpenFile: (PaneID) -> Void

    @State private var isTerminalLauncherPickerPresented = false

    private var showsTerminalLauncherPicker: Bool {
        canLaunchClaude || canLaunchCodex
    }

    var body: some View {
        VStack(spacing: DevysSpacing.space5) {
            VStack(spacing: DevysSpacing.space2) {
                Text("Open a file, preview a local app, start a terminal, or launch an agent")
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            HStack(spacing: DevysSpacing.space2) {
                ActionButton("Terminal", icon: "terminal", style: .primary) {
                    onFocusPane(paneID)
                    if showsTerminalLauncherPicker {
                        isTerminalLauncherPickerPresented = true
                    } else {
                        onOpenTerminal(paneID)
                    }
                }

                ActionButton("Browser", icon: "globe", style: .ghost) {
                    onFocusPane(paneID)
                    onOpenBrowser(paneID)
                }

                ActionButton("Agent", icon: "person.crop.circle.badge.plus", style: .ghost) {
                    onFocusPane(paneID)
                    onOpenAgent(paneID)
                }

                ActionButton("Open File", icon: "doc", style: .ghost) {
                    onFocusPane(paneID)
                    onOpenFile(paneID)
                }
            }
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
}

private struct TerminalLauncherPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let canLaunchClaude: Bool
    let canLaunchCodex: Bool
    let onOpenShell: () -> Void
    let onOpenClaude: () -> Void
    let onOpenCodex: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space4) {
            Text("Open Terminal")
                .font(DevysTypography.title)
                .foregroundStyle(theme.text)

            Text("Choose a plain shell or launch a configured agent terminal for this workspace.")
                .font(DevysTypography.body)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space3) {
                launcherButton(
                    title: "Shell",
                    subtitle: "Open a plain shell",
                    icon: "terminal",
                    action: onOpenShell
                )

                if canLaunchClaude {
                    launcherButton(
                        title: "Claude Code",
                        subtitle: "Use repository launcher settings",
                        icon: DevysIconName.claudeCode,
                        action: onOpenClaude
                    )
                }

                if canLaunchCodex {
                    launcherButton(
                        title: "Codex",
                        subtitle: "Use repository launcher settings",
                        icon: DevysIconName.codex,
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
        .padding(DevysSpacing.space5)
        .frame(width: 560)
        .elevation(.overlay)
    }

    private func launcherButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            VStack(alignment: .leading, spacing: DevysSpacing.space3) {
                DevysIcon(icon, size: 18)
                    .foregroundStyle(theme.accent)

                Text(title)
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.text)

                Text(subtitle)
                    .font(DevysTypography.body)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(DevysSpacing.space4)
            .elevation(.card)
        }
        .buttonStyle(.plain)
    }
}
