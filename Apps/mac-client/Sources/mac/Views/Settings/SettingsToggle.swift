import SwiftUI
import UI

struct SettingsToggle: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)

                Text(description)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(theme.accent)
                .labelsHidden()
        }
    }
}
