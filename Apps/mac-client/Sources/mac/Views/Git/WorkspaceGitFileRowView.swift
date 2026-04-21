import Git
import SwiftUI
import UI
import Workspace

@MainActor
struct WorkspaceGitFileRowView: View {
    @Environment(\.devysTheme) private var theme

    let file: GitFileChange
    let isStaged: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: (() -> Void)?
    let onAddToChat: (() -> Void)?
    let onStage: (() -> Void)?
    let onUnstage: (() -> Void)?
    let onDiscard: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: file.status.iconName)
                .font(Typography.micro)
                .foregroundStyle(statusColor)
                .frame(width: 14)

            Text(file.filename)
                .font(Typography.Code.sm)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    if let onStage {
                        actionButton(
                            icon: "plus.circle.fill",
                            color: DevysColors.success,
                            help: "Stage",
                            action: onStage
                        )
                    }

                    if let onUnstage {
                        actionButton(
                            icon: "minus.circle.fill",
                            color: DevysColors.warning,
                            help: "Unstage",
                            action: onUnstage
                        )
                    }

                    if let onDiscard {
                        actionButton(
                            icon: "xmark.circle.fill",
                            color: DevysColors.error,
                            help: "Discard",
                            action: onDiscard
                        )
                    }
                }
            } else if !file.directory.isEmpty && file.directory != "." {
                Text(file.directory)
                    .font(Typography.Code.gutter)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space1)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onOpen?()
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(GitDiffTransfer(path: file.path, isStaged: isStaged)) {
            HStack(spacing: Spacing.space2) {
                Image(systemName: file.status.iconName)
                    .font(Typography.micro)
                    .foregroundStyle(statusColor)
                Text(file.filename)
                    .font(Typography.Code.gutter.weight(.medium))
                    .lineLimit(1)
                Text(isStaged ? "Staged" : "Unstaged")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
            .background(theme.overlay)
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        }
        .contextMenu {
            Button {
                onOpen?()
            } label: {
                Label("View Diff", systemImage: "arrow.left.arrow.right")
            }

            if let onAddToChat {
                Button(action: onAddToChat) {
                    Label("Add Diff to Chat", systemImage: "bubble.left.and.text.bubble.right")
                }
            }

            Divider()

            if let onStage {
                Button(action: onStage) {
                    Label("Stage", systemImage: "plus.circle")
                }
            }

            if let onUnstage {
                Button(action: onUnstage) {
                    Label("Unstage", systemImage: "minus.circle")
                }
            }

            if let onDiscard {
                Divider()
                Button(role: .destructive, action: onDiscard) {
                    Label("Discard Changes", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func actionButton(
        icon: String,
        color: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Typography.label)
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: Color {
        if isSelected {
            return theme.accentMuted
        }
        if isHovered {
            return theme.hover
        }
        return .clear
    }

    private var statusColor: Color {
        switch file.status {
        case .modified:
            DevysColors.warning
        case .added:
            DevysColors.success
        case .deleted:
            DevysColors.error
        case .renamed, .untracked:
            theme.textSecondary
        case .unmerged:
            DevysColors.error
        case .copied:
            .purple
        case .ignored:
            theme.textTertiary
        }
    }
}
