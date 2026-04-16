// Breadcrumb.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Titlebar context breadcrumb.
///
/// Shows a compact trail of navigation segments separated by "/" dividers.
/// Segments can have icons, agent-identity color dots, and click actions.
public struct Breadcrumb: View {
    @Environment(\.theme) private var theme

    private let segments: [BreadcrumbSegment]

    public init(segments: [BreadcrumbSegment]) {
        self.segments = segments
    }

    public var body: some View {
        HStack(spacing: Spacing.space1) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Text("/")
                        .font(Typography.label)
                        .foregroundStyle(theme.textTertiary)
                }

                BreadcrumbSegmentView(segment: segment)
            }
        }
    }
}

// MARK: - Segment Model

public struct BreadcrumbSegment {
    public let title: String
    public let icon: String?
    public let color: Color?
    public let action: (() -> Void)?

    public init(
        title: String,
        icon: String? = nil,
        color: Color? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }
}

// MARK: - Segment View

private struct BreadcrumbSegmentView: View {
    @Environment(\.theme) private var theme

    let segment: BreadcrumbSegment

    @State private var isHovered = false

    var body: some View {
        let content = HStack(spacing: 4) {
            // Agent color dot
            if let color = segment.color {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            // Icon
            if let icon = segment.icon {
                Image(systemName: icon)
                    .font(Typography.micro)
                    .foregroundStyle(labelColor)
            }

            // Title
            Text(segment.title)
                .font(Typography.label)
                .foregroundStyle(labelColor)
                .underline(isHovered && segment.action != nil)
        }

        if let action = segment.action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(Animations.micro) { isHovered = hovering }
                }
        } else {
            content
        }
    }

    private var labelColor: Color {
        if isHovered && segment.action != nil {
            return theme.text
        }
        return theme.textSecondary
    }
}

// MARK: - Previews

#Preview("Breadcrumb") {
    VStack(spacing: Spacing.space4) {
        Breadcrumb(segments: [
            BreadcrumbSegment(title: "devys", icon: "folder"),
            BreadcrumbSegment(title: "Sources", icon: "folder"),
            BreadcrumbSegment(title: "ContentView.swift") {},
        ])

        Breadcrumb(segments: [
            BreadcrumbSegment(
                title: "API Refactor",
                color: AgentColor.forIndex(1).solid
            ) {},
            BreadcrumbSegment(title: "auth.swift", icon: "doc"),
        ])

        Breadcrumb(segments: [
            BreadcrumbSegment(title: "devys", icon: "laptopcomputer"),
            BreadcrumbSegment(
                title: "Claude",
                color: AgentColor.forIndex(2).solid
            ),
            BreadcrumbSegment(title: "Chat") {},
        ])
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
