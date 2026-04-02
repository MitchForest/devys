import SwiftUI
import UI

struct IOSAssistantIntegrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    @Binding var statuses: [IOSAssistantMode: IOSAssistantIntegrationStatus]

    @State private var pendingDisconnectMode: IOSAssistantMode?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.space2) {
                    ForEach(IOSAssistantMode.allCases) { mode in
                        integrationRow(mode: mode)
                    }
                }
                .padding(DevysSpacing.space4)
            }
            .background(theme.base)
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert(
            "Disconnect \(pendingDisconnectMode?.title ?? "")?",
            isPresented: disconnectAlertBinding,
            actions: {
                Button("Cancel", role: .cancel) {
                    pendingDisconnectMode = nil
                }
                Button("Disconnect", role: .destructive) {
                    disconnectPendingMode()
                }
            },
            message: {
                Text("The integration can be reconnected at any time.")
            }
        )
    }

    private var disconnectAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDisconnectMode != nil },
            set: { if !$0 { pendingDisconnectMode = nil } }
        )
    }

    private func integrationRow(mode: IOSAssistantMode) -> some View {
        let status = statuses[mode] ?? .disconnected

        return HStack(spacing: DevysSpacing.space3) {
            Image(systemName: mode.icon)
                .font(.system(size: DevysSpacing.iconMd))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DevysSpacing.space2) {
                    Text(mode.title)
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)
                    statusPill(status)
                }

                Text("Scopes: \(mode.scopesSummary)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                Text("Last sync: \(lastSyncLabel(mode: mode, status: status))")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 0)

            Button(status == .connected ? "Disconnect" : "Connect") {
                handleAction(mode: mode, status: status)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DevysSpacing.space2)
            .padding(.vertical, DevysSpacing.space1)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .foregroundStyle(theme.textSecondary)
        }
        .padding(DevysSpacing.space3)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusLg))
        .overlay {
            RoundedRectangle(cornerRadius: DevysSpacing.radiusLg)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        }
    }

    private func statusPill(_ status: IOSAssistantIntegrationStatus) -> some View {
        let color: Color
        switch status {
        case .connected:
            color = DevysColors.success
        case .disconnected:
            color = theme.textTertiary
        case .error:
            color = DevysColors.error
        }

        return Text(status.pillText)
            .font(DevysTypography.xs)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func handleAction(mode: IOSAssistantMode, status: IOSAssistantIntegrationStatus) {
        switch status {
        case .connected:
            pendingDisconnectMode = mode
        case .disconnected, .error:
            withAnimation(DevysAnimation.modal) {
                statuses[mode] = .connected
            }
        }
    }

    private func disconnectPendingMode() {
        guard let mode = pendingDisconnectMode else { return }
        withAnimation(DevysAnimation.modal) {
            statuses[mode] = .disconnected
        }
        pendingDisconnectMode = nil
    }

    private func lastSyncLabel(mode: IOSAssistantMode, status: IOSAssistantIntegrationStatus) -> String {
        switch status {
        case .connected:
            switch mode {
            case .calendar:
                return "just now"
            case .gmail:
                return "2m ago"
            case .gchat:
                return "5m ago"
            }
        case .disconnected:
            return "paused"
        case .error:
            return "sync failed"
        }
    }
}
