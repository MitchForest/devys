// FABMenu.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Data Models

/// A single menu item in the FAB menu.
public struct FABMenuItem: Sendable {
    public let icon: String
    public let title: String
    public let shortcut: String?
    public let isEnabled: Bool
    public let action: @Sendable () -> Void

    public init(
        icon: String,
        title: String,
        shortcut: String? = nil,
        isEnabled: Bool = true,
        action: @escaping @Sendable () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// A section grouping menu items with an optional header.
public struct FABMenuSection: Sendable {
    public let title: String?
    public let items: [FABMenuItem]

    public init(title: String? = nil, items: [FABMenuItem]) {
        self.title = title
        self.items = items
    }
}

// MARK: - FAB Button

/// A 28x28 circular floating action button with a plus icon.
///
/// Tap toggles the menu open state. Hover and press states provide feedback.
public struct FABButton: View {
    @Environment(\.theme) private var theme

    @Binding var isMenuOpen: Bool

    @State private var isHovered = false
    @State private var isPressed = false

    public init(isMenuOpen: Binding<Bool>) {
        self._isMenuOpen = isMenuOpen
    }

    public var body: some View {
        Button {
            isMenuOpen.toggle()
        } label: {
            Image(systemName: "plus")
                .font(Typography.heading.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    isHovered ? theme.accent : theme.accent,
                    in: Circle()
                )
                .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
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
    }
}

// MARK: - FAB Menu Content

/// Popover menu content for the FAB, displaying grouped actions.
///
/// Each section has an optional header. Rows show icon, title, and optional shortcut badge.
public struct FABMenuContent: View {
    @Environment(\.theme) private var theme
    private let sections: [FABMenuSection]

    public init(sections: [FABMenuSection]) {
        self.sections = sections
    }

    /// Convenience for a flat list without sections.
    public init(items: [FABMenuItem]) {
        self.sections = [FABMenuSection(items: items)]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                if sectionIndex > 0 {
                    Separator()
                        .padding(.vertical, Spacing.space1)
                }

                if let title = section.title {
                    SectionHeader(title)
                        .padding(.horizontal, Spacing.space2)
                        .padding(.top, sectionIndex > 0 ? 0 : Spacing.space1)
                }

                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    FABMenuRow(item: item)
                }
            }
        }
        .padding(.vertical, Spacing.space2)
        .frame(width: 260)
        .background(theme.overlay, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .shadowStyle(Shadows.md)
        .transition(
            .scale(scale: 0.95, anchor: .bottom)
            .combined(with: .opacity)
        )
    }
}

// MARK: - FAB Menu Row

private struct FABMenuRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    let item: FABMenuItem

    @State private var isHovered = false

    var body: some View {
        Button {
            item.action()
        } label: {
            HStack(spacing: Spacing.space2) {
                Image(systemName: item.icon)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(item.isEnabled ? theme.textSecondary : theme.textTertiary)
                    .frame(width: 18)

                Text(item.title)
                    .font(Typography.body)
                    .foregroundStyle(item.isEnabled ? theme.text : theme.textTertiary)

                Spacer(minLength: 4)

                if let shortcut = item.shortcut {
                    ShortcutBadge(shortcut)
                }
            }
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.space1)
            .frame(minHeight: layout.sidebarRowHeight)
            .background(
                isHovered && item.isEnabled ? theme.hover : .clear,
                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            )
            .padding(.horizontal, Spacing.space1)
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }
}

// MARK: - Previews

#Preview("FAB Menu") {
    struct Demo: View {
        @State var isOpen = false

        var body: some View {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.space2) {
                        if isOpen {
                            FABMenuContent(sections: [
                                FABMenuSection(title: "Create", items: [
                                    FABMenuItem(icon: "doc", title: "New File", shortcut: "Cmd+N") {},
                                    FABMenuItem(icon: "folder", title: "New Folder", shortcut: "Cmd+Shift+N") {},
                                ]),
                                FABMenuSection(title: "Agent", items: [
                                    FABMenuItem(icon: "sparkles", title: "Start Agent", shortcut: "Cmd+L") {},
                                    FABMenuItem(icon: "terminal", title: "Open Terminal", shortcut: "Cmd+`") {},
                                    FABMenuItem(icon: "arrow.triangle.branch", title: "Create Branch") {},
                                    FABMenuItem(icon: "tray", title: "Archived", isEnabled: false) {},
                                ]),
                            ])
                            .animation(Animations.spring, value: isOpen)
                        }
                        FABButton(isMenuOpen: $isOpen)
                    }
                    .padding(Spacing.space4)
                }
            }
            .frame(width: 340, height: 500)
            .background(Color(hex: "#121110"))
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}
