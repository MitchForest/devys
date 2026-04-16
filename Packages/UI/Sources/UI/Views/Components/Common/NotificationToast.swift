// NotificationToast.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Ephemeral notification toast with auto-dismiss.
///
/// Slides up into view with the signature spring and fades out after a timeout.
/// An optional accent color adds a left border for agent identity.
public struct NotificationToast: View {
    @Environment(\.theme) private var theme

    private let message: String
    private let icon: String?
    private let accentColor: Color?
    private let autoDismissAfter: TimeInterval
    private let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var isDismissHovered = false

    public init(
        message: String,
        icon: String? = nil,
        accentColor: Color? = nil,
        autoDismissAfter: TimeInterval = 4,
        onDismiss: @escaping () -> Void
    ) {
        self.message = message
        self.icon = icon
        self.accentColor = accentColor
        self.autoDismissAfter = autoDismissAfter
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            // Accent left border
            if let accentColor {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 2)
                    .padding(.vertical, Spacing.space1)
            }

            // Icon
            if let icon {
                Image(systemName: icon)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(accentColor ?? theme.textSecondary)
            }

            // Message
            Text(message)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(2)

            Spacer(minLength: Spacing.space2)

            // Dismiss button
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(isDismissHovered ? theme.text : theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(
                        isDismissHovered ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .onHover { h in
                withAnimation(Animations.micro) { isDismissHovered = h }
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .shadowStyle(Shadows.md)
        .offset(y: isVisible ? 0 : 16)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(Animations.spring) {
                isVisible = true
            }
            startAutoDismiss()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    // MARK: - Auto-Dismiss

    private func startAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        // Delay the callback to let the animation finish
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onDismiss()
        }
    }
}

// MARK: - Previews

#Preview("Notification Toasts") {
    VStack(spacing: Spacing.space3) {
        NotificationToast(
            message: "Build succeeded",
            icon: "checkmark.circle.fill",
            autoDismissAfter: 60
        ) {}

        NotificationToast(
            message: "Agent completed: API refactor",
            icon: "sparkles",
            accentColor: AgentColor.forIndex(1).solid,
            autoDismissAfter: 60
        ) {}

        NotificationToast(
            message: "3 files changed on disk",
            icon: "doc.badge.arrow.up",
            autoDismissAfter: 60
        ) {}

        NotificationToast(
            message: "Connection lost. Retrying...",
            icon: "wifi.exclamationmark",
            accentColor: Colors.warning,
            autoDismissAfter: 60
        ) {}
    }
    .frame(width: 320)
    .padding(40)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
