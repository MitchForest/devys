// TabPill.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// An individual tab in the tab bar.
///
/// Supports selection, preview (italic), dirty indicators, agent identity stripes,
/// hover/press micro-interactions, and an inline close button.
public struct TabPill: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let title: String
    private let icon: String?
    private let isSelected: Bool
    private let isPreview: Bool
    private let isDirty: Bool
    private let activityStatus: StatusDot.Status?
    private let agentColor: AgentColor?
    private let agentStatus: AgentStatus?
    private let minWidth: CGFloat?
    private let maxWidth: CGFloat?
    private let height: CGFloat?
    private let onSelect: () -> Void
    private let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false
    @State private var isPressed = false
    @State private var dirtyDotScale: CGFloat = 1.0

    public init(
        title: String,
        icon: String? = nil,
        isSelected: Bool = false,
        isPreview: Bool = false,
        isDirty: Bool = false,
        activityStatus: StatusDot.Status? = nil,
        agentColor: AgentColor? = nil,
        agentStatus: AgentStatus? = nil,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        height: CGFloat? = nil,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.isPreview = isPreview
        self.isDirty = isDirty
        self.activityStatus = activityStatus
        self.agentColor = agentColor
        self.agentStatus = agentStatus
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.height = height
        self.onSelect = onSelect
        self.onClose = onClose
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Agent identity stripe on leading edge
                if let agentColor {
                    AgentIdentityStripe(
                        color: agentColor,
                        status: agentStatus ?? .idle,
                        width: 2,
                        edge: .leading
                    )
                }

                HStack(spacing: Spacing.space1) {
                    // Icon
                    if let icon {
                        DevysIcon(icon, size: 14)
                            .foregroundStyle(iconColor)
                    }

                    // Title
                    Text(title)
                        .font(Typography.label)
                        .italic(isPreview)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    if let activityStatus {
                        StatusDot(activityStatus, size: 6)
                    }

                    Spacer(minLength: Spacing.space1)

                    // Dirty dot + close button area
                    closeArea
                }
                .padding(.horizontal, Spacing.space2)
            }
            .frame(height: height ?? layout.tabHeight)
            .frame(
                minWidth: minWidth ?? Spacing.tabMinWidth,
                maxWidth: maxWidth ?? Spacing.tabMaxWidth
            )
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .overlay(alignment: .bottom) {
                // Accent bottom border for selected tab
                if isSelected {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(theme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, Spacing.space1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .opacity(isPreview ? 0.85 : 1.0)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(Animations.micro) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(Animations.micro) { isPressed = false }
                }
        )
        .onChange(of: isDirty) { _, newValue in
            guard newValue else { return }
            // Pulse the dirty dot once: scale 1.0 → 1.3 → 1.0
            withAnimation(Animations.glow) {
                dirtyDotScale = 1.3
            }
            withAnimation(Animations.glow.delay(0.15)) {
                dirtyDotScale = 1.0
            }
        }
        .help(title)
    }

    // MARK: - Close Area

    @ViewBuilder
    private var closeArea: some View {
        if isSelected || isHovered {
            ZStack {
                // Dirty indicator: 4pt warning dot, hidden when close is hovered
                if isDirty && !isCloseHovered {
                    Circle()
                        .fill(theme.warning)
                        .frame(width: 4, height: 4)
                        .scaleEffect(dirtyDotScale)
                        .transition(.opacity)
                }

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Typography.micro)
                        .foregroundStyle(isCloseHovered ? theme.text : theme.textTertiary)
                        .frame(width: 16, height: 16)
                        .background(
                            isCloseHovered
                                ? theme.active
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(Animations.micro) { isCloseHovered = hovering }
                }
            }
            .frame(width: 16, height: 16)
            .transition(.opacity)
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        if isSelected {
            return theme.card
        }
        return isHovered ? theme.overlay : .clear
    }

    private var titleColor: Color {
        isSelected ? theme.text : theme.textSecondary
    }

    private var iconColor: Color {
        isSelected ? theme.text : theme.textTertiary
    }
}

// MARK: - Previews

#Preview("Tab Pills") {
    let theme = Theme(isDark: true)
    VStack(spacing: Spacing.space4) {
        // Row 1: Basic states
        HStack(spacing: Spacing.space1) {
            TabPill(
                title: "AppDelegate.swift",
                icon: "swift",
                isSelected: true,
                isDirty: true,
                onSelect: {},
                onClose: {}
            )
            TabPill(
                title: "Package.swift",
                icon: "shippingbox",
                onSelect: {},
                onClose: {}
            )
            TabPill(
                title: "Preview File",
                isPreview: true,
                onSelect: {},
                onClose: {}
            )
        }

        // Row 2: Agent tabs
        HStack(spacing: Spacing.space1) {
            TabPill(
                title: "API Refactor",
                icon: "doc",
                isSelected: true,
                agentColor: .forIndex(1),
                agentStatus: .running,
                onSelect: {},
                onClose: {}
            )
            TabPill(
                title: "Tests Agent",
                agentColor: .forIndex(2),
                agentStatus: .complete,
                onSelect: {},
                onClose: {}
            )
            TabPill(
                title: "Build Fix",
                agentColor: .forIndex(0),
                agentStatus: .error,
                onSelect: {},
                onClose: {}
            )
        }
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, theme)
    .environment(\.densityLayout, DensityLayout(.comfortable))
}
