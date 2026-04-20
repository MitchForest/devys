import SwiftUI
import UI

struct AddRepositorySheet: View {
    @Environment(\.theme) private var theme

    let onSelectLocal: () -> Void
    let onSelectSSH: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Sheet(
            title: "Add Repository",
            secondaryAction: SheetAction(title: "Cancel", action: onCancel),
            onDismiss: onCancel
        ) {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                Text("Choose where the repository lives. Local and SSH repositories can sit together in the rail.")
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)

                VStack(spacing: Spacing.space3) {
                    optionCard(
                        title: "Local Repository",
                        subtitle: "Open a folder from this Mac.",
                        detail: "Best for active local worktrees and direct file access.",
                        icon: "folder",
                        action: onSelectLocal
                    )

                    optionCard(
                        title: "Remote via SSH",
                        subtitle: "Pick a saved host, then connect a repository path on that machine.",
                        detail: "Uses your system SSH config plus recent remote connections.",
                        icon: "server.rack",
                        action: onSelectSSH
                    )
                }
            }
        }
        .frame(width: 560)
    }

    private func optionCard(
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.space3) {
                Image(systemName: icon)
                    .font(Typography.heading)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28, height: 28)
                    .background(theme.accentSubtle, in: Circle())

                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text(title)
                        .font(Typography.heading)
                        .foregroundStyle(theme.text)

                    Text(subtitle)
                        .font(Typography.body)
                        .foregroundStyle(theme.textSecondary)

                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(Spacing.space4)
            .background(theme.card, in: DevysShape())
            .overlay {
                DevysShape()
                    .stroke(theme.border, lineWidth: Spacing.borderWidth)
            }
            .contentShape(DevysShape())
        }
        .buttonStyle(.plain)
    }
}
