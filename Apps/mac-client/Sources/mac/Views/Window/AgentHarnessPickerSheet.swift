import ACPClientKit
import SwiftUI
import UI

struct AgentHarnessPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let onSelect: (ACPAgentKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space4) {
            Text("Open Agents")
                .font(DevysTypography.title)
                .foregroundStyle(theme.text)

            Text("Choose which ACP adapter should back this Agents tab.")
                .font(DevysTypography.body)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space3) {
                pickerButton(
                    title: "Codex",
                    subtitle: "OpenAI Codex ACP",
                    icon: "chevron.left.forwardslash.chevron.right",
                    kind: .codex
                )
                pickerButton(
                    title: "Claude",
                    subtitle: "Claude Code ACP",
                    icon: "brain",
                    kind: .claude
                )
            }

            HStack {
                Spacer()
                ActionButton("Cancel", style: .ghost) {
                    onCancel()
                    dismiss()
                }
            }
        }
        .padding(DevysSpacing.space5)
        .frame(width: 460)
        .elevation(.overlay)
    }

    private func pickerButton(
        title: String,
        subtitle: String,
        icon: String,
        kind: ACPAgentKind
    ) -> some View {
        Button {
            onSelect(kind)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: DevysSpacing.space3) {
                Image(systemName: icon)
                    .font(DevysTypography.title)
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
