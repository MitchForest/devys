// AgentRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// An agent entry in the sidebar agent list.
///
/// Shows an identity-colored dot (pulsing when running), the agent name,
/// and a status chip. Hover reveals rename/stop action buttons at the right edge.
public struct AgentRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let name: String
    private let agentColor: AgentColor
    private let status: AgentStatus
    private let subtitle: String?
    private let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPulsing = false

    public init(
        name: String,
        agentColor: AgentColor,
        status: AgentStatus,
        subtitle: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.name = name
        self.agentColor = agentColor
        self.status = status
        self.subtitle = subtitle
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.space2) {
                // Identity dot
                identityDot

                // Agent name
                Text(name)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)

                Spacer(minLength: Spacing.space1)

                if isHovered {
                    hoverActions
                } else {
                    statusChip
                }
            }
            .padding(.horizontal, layout.itemPaddingH)
            .frame(height: layout.sidebarRowHeight)
            .background(
                isHovered ? theme.hover : .clear,
                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    // MARK: - Identity Dot

    private var identityDot: some View {
        Circle()
            .fill(agentColor.solid)
            .frame(width: 8, height: 8)
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

    // MARK: - Status Chip

    @ViewBuilder
    private var statusChip: some View {
        switch status {
        case .running:
            if let subtitle {
                Chip(.status(subtitle, theme.success))
            } else {
                Chip(.status("Running", theme.success))
            }

        case .waiting:
            Chip(.status("Waiting", theme.warning))

        case .complete:
            Chip(.status("Complete", theme.textTertiary))

        case .error:
            Chip(.status("Error", theme.error))

        case .idle:
            Chip(.status("Idle", theme.textTertiary))
        }
    }

    // MARK: - Hover Actions

    private var hoverActions: some View {
        HStack(spacing: Spacing.space1) {
            ActionButton("Rename", icon: "pencil", style: .ghost) {}
                .controlSize(.small)

            if status == .running || status == .waiting {
                ActionButton(
                    "Stop",
                    icon: "stop.fill",
                    style: .ghost,
                    tone: .destructive
                ) {}
                    .controlSize(.small)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Computed Properties

    private var nameColor: Color {
        switch status {
        case .running, .waiting:
            theme.text
        case .complete, .error, .idle:
            theme.textSecondary
        }
    }
}

// MARK: - Previews

#Preview("Agent Rows") {
    VStack(spacing: 0) {
        AgentRow(
            name: "API Refactor",
            agentColor: .forIndex(0),
            status: .running,
            subtitle: "Working on auth.swift"
        ) {}
        AgentRow(
            name: "Test Writer",
            agentColor: .forIndex(1),
            status: .waiting
        ) {}
        AgentRow(
            name: "Bug Fix #42",
            agentColor: .forIndex(2),
            status: .complete
        ) {}
        AgentRow(
            name: "Deploy Pipeline",
            agentColor: .forIndex(3),
            status: .error
        ) {}
        AgentRow(
            name: "Code Review",
            agentColor: .forIndex(4),
            status: .idle
        ) {}
    }
    .frame(width: 300)
    .padding(.vertical, Spacing.space2)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
