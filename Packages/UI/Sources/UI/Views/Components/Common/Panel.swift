// Panel.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Panel scaffold with optional header, content, and optional footer.
///
/// Use for sidebar sections, inspector panels, any contained surface area.
public struct Panel<Content: View>: View {
    @Environment(\.theme) private var theme

    private let title: String?
    private let content: Content

    public init(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                SectionHeader(title)
                    .padding(.horizontal, Spacing.space4)
                    .padding(.vertical, Spacing.space3)
                Separator()
            }

            content
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }
}

/// A collapsible sidebar section with disclosure and optional trailing action.
public struct SidebarSection<Content: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let icon: String?
    private let count: Int?
    private let actionIcon: String?
    private let action: (() -> Void)?
    @Binding private var isExpanded: Bool
    private let content: Content

    @State private var isActionHovered = false

    public init(
        _ title: String,
        icon: String? = nil,
        count: Int? = nil,
        actionIcon: String? = nil,
        action: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.actionIcon = actionIcon
        self.action = action
        self._isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.space2) {
                Button {
                    withAnimation(Animations.micro) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.space2) {
                        Image(systemName: "chevron.right")
                            .font(Typography.micro.weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(Animations.micro, value: isExpanded)
                            .frame(width: 12)

                        if let icon {
                            Image(systemName: icon)
                                .font(Typography.caption.weight(.medium))
                                .foregroundStyle(theme.textTertiary)
                        }

                        Text(title)
                            .font(Typography.heading)
                            .foregroundStyle(theme.textSecondary)

                        if let count {
                            Chip(.count(count))
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let actionIcon, let action {
                    Button(action: action) {
                        Image(systemName: actionIcon)
                            .font(Typography.label)
                            .foregroundStyle(isActionHovered ? theme.text : theme.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(
                                isActionHovered ? theme.hover : .clear,
                                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        withAnimation(Animations.micro) { isActionHovered = h }
                    }
                }
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

// MARK: - Previews

#Preview("Panel") {
    VStack(spacing: Spacing.space4) {
        Panel(title: "Details") {
            VStack(spacing: 0) {
                ListRow(icon: "doc", title: "Package.swift")
                ListRow(icon: "folder", title: "Sources")
            }
            .padding(.vertical, Spacing.space1)
        }
    }
    .frame(width: 280)
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
