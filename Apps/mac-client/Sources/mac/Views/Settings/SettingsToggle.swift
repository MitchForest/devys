import SwiftUI
import UI

struct SettingsToggle: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.text)

                Text(description)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Button {
                isOn.toggle()
            } label: {
                Text(isOn ? "[ON ]" : "[OFF]")
                    .font(DevysTypography.sm)
                    .foregroundStyle(isOn ? theme.accent : theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}
