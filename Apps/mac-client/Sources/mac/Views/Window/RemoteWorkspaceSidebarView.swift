import AppFeatures
import RemoteCore
import SwiftUI
import UI

struct RemoteWorkspaceSidebarView: View {
    @Environment(\.theme) private var theme

    let activeSidebar: WorkspaceSidebarMode
    let repository: RemoteRepositoryAuthority?
    let worktree: RemoteWorktree?
    let onRefresh: () -> Void
    let onFetch: () -> Void
    let onPull: () -> Void
    let onPush: () -> Void
    let onCreateWorktree: () -> Void
    let onOpenShell: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.space4) {
                    group("Remote") {
                        metadataLine("Host", value: repository?.sshTarget)
                        metadataLine("Repository", value: repository?.repositoryPath)
                        metadataLine("Worktree", value: worktree?.remotePath)
                        metadataLine("Branch", value: worktree?.branchName)
                    }

                    group("Git") {
                        actionRow("Refresh", icon: "arrow.clockwise", action: onRefresh)
                        actionRow("Fetch", icon: "arrow.down.circle", action: onFetch)
                        actionRow("Pull", icon: "arrow.down.to.line", action: onPull, enabled: worktree != nil)
                        actionRow("Push", icon: "arrow.up.to.line", action: onPush, enabled: worktree != nil)
                        actionRow("New Worktree", icon: "plus.square.on.square", action: onCreateWorktree)
                    }

                    group("Sessions") {
                        actionRow("Shell Session", icon: "terminal", action: onOpenShell, enabled: worktree != nil)
                    }
                }
                .padding(Spacing.space3)
            }

            Spacer(minLength: 0)
        }
        .background(theme.base)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(activeSidebar == .agents ? "Remote Sessions" : "Remote Workspace")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.text)
            Text("SSH-backed authorities stay terminal-centric in phase 1.")
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(Spacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text(title)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.space1) {
                content()
            }
            .padding(Spacing.space3)
            .elevation(.card)
        }
    }

    private func metadataLine(
        _ title: String,
        value: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
            Text(value?.isEmpty == false ? value ?? "" : "Unavailable")
                .font(Typography.caption)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
        }
    }

    private func actionRow(
        _ title: String,
        icon: String,
        action: @escaping () -> Void,
        enabled: Bool = true
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.space2) {
                DevysIcon(icon, size: 14)
                    .foregroundStyle(enabled ? theme.accent : theme.textTertiary)
                    .frame(width: 18)
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(enabled ? theme.text : theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.space1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
