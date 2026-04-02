// AssistantIntegrationSheet.swift
// Phase 1 integration management sheet.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct AssistantIntegrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    @Binding var integrationStatuses: [AssistantMode: AssistantIntegrationStatus]

    @State private var pendingDisconnectMode: AssistantMode?

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space4) {
            HStack {
                Text("Integrations")
                    .font(DevysTypography.title)
                    .foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
            }

            VStack(spacing: DevysSpacing.space2) {
                ForEach(AssistantMode.allCases) { mode in
                    integrationRow(for: mode)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DevysSpacing.space5)
        .frame(width: 520, height: 360)
        .background(theme.base)
        .alert(
            "Disconnect \(pendingDisconnectMode?.title ?? "")?",
            isPresented: disconnectAlertBinding,
            actions: {
                Button("Cancel", role: .cancel) {
                    pendingDisconnectMode = nil
                }
                Button("Disconnect", role: .destructive) {
                    disconnectSelectedMode()
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

    private func integrationRow(for mode: AssistantMode) -> some View {
        let status = integrationStatuses[mode] ?? .disconnected

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
                    statusPill(for: status)
                }

                Text("Scopes: \(mode.scopesSummary)")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                Text("Last sync: \(lastSyncLabel(for: mode, status: status))")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 0)

            Button(status == .connected ? "Disconnect" : "Connect") {
                handleAction(for: mode, status: status)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DevysSpacing.space2)
            .padding(.vertical, DevysSpacing.space1)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .overlay {
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            }
            .foregroundStyle(theme.textSecondary)
            .accessibilityLabel("\(status == .connected ? "Disconnect" : "Connect") \(mode.title)")
        }
        .padding(DevysSpacing.space3)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusLg))
        .overlay {
            RoundedRectangle(cornerRadius: DevysSpacing.radiusLg)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusPill(for status: AssistantIntegrationStatus) -> some View {
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

    private func lastSyncLabel(for mode: AssistantMode, status: AssistantIntegrationStatus) -> String {
        switch status {
        case .connected:
            return mode.defaultLastSync
        case .disconnected:
            return "paused"
        case .error:
            return "sync failed"
        }
    }

    private func handleAction(for mode: AssistantMode, status: AssistantIntegrationStatus) {
        switch status {
        case .connected:
            pendingDisconnectMode = mode
        case .disconnected, .error:
            withAnimation(DevysAnimation.modal) {
                integrationStatuses[mode] = .connected
            }
        }
    }

    private func disconnectSelectedMode() {
        guard let mode = pendingDisconnectMode else { return }
        withAnimation(DevysAnimation.modal) {
            integrationStatuses[mode] = .disconnected
        }
        pendingDisconnectMode = nil
    }
}
