// StatusIndicator.swift → StatusDot
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A colored dot communicating status at a glance.
///
/// Running status gets a heartbeat pulse. Completion gets a brief glow.
/// Errors are static — they need attention, not anxiety.
public struct StatusDot: View {
    @Environment(\.theme) private var theme

    private let status: Status
    private let size: CGFloat

    @State private var isPulsing = false

    public init(_ status: Status, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(status.color(theme: theme))
            .frame(width: size, height: size)
            .opacity(status == .running ? (isPulsing ? 1.0 : 0.6) : 1.0)
            .animation(
                status == .running ? Animations.heartbeat : nil,
                value: isPulsing
            )
            .onAppear {
                if status == .running { isPulsing = true }
            }
            .onChange(of: status) { _, newStatus in
                isPulsing = newStatus == .running
            }
    }
}

// MARK: - Status

public extension StatusDot {
    enum Status: String, Sendable, CaseIterable {
        case running
        case waiting
        case complete
        case error
        case idle

        public func color(theme: Theme) -> Color {
            switch self {
            case .running: theme.success
            case .waiting: theme.warning
            case .complete: theme.textTertiary
            case .error: theme.error
            case .idle: theme.textTertiary
            }
        }
    }
}

// MARK: - Previews

#Preview("Status Dots") {
    HStack(spacing: Spacing.space6) {
        ForEach(StatusDot.Status.allCases, id: \.self) { status in
            VStack(spacing: Spacing.space2) {
                StatusDot(status)
                Text(status.rawValue)
                    .font(Typography.caption)
            }
        }
    }
    .foregroundStyle(Color(hex: "#9E978C"))
    .padding()
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
