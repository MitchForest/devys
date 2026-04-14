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
                .font(DevysTypography.lg)
                .foregroundStyle(theme.text)

            Text("Choose which ACP adapter should back this Agents tab.")
                .font(DevysTypography.base)
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
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
            }
        }
        .padding(DevysSpacing.space5)
        .frame(width: 460)
        .background(theme.base)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.visibleAccent)

                Text(title)
                    .font(DevysTypography.base)
                    .foregroundStyle(theme.text)

                Text(subtitle)
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(DevysSpacing.space4)
            .background(theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
