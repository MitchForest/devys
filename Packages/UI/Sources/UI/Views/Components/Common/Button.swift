// ActionButton.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A button with clear affordance and proper interactive states.
///
/// Styles:
/// - **primary**: Filled background for the main action in a group.
/// - **ghost**: Quiet action with hover affordance only.
///
/// Tone:
/// - **standard**: Normal action coloring.
/// - **destructive**: Semantic error coloring applied to either style.
public struct ActionButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let icon: String?
    private let style: Style
    private let tone: Tone
    private let isLoading: Bool
    private let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    public init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        tone: Tone = .standard,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.tone = tone
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.space1) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .progressViewStyle(.circular)
                } else if let icon {
                    Image(systemName: icon)
                    Text(title)
                } else {
                    Text(title)
                }
            }
            .font(Typography.label)
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: Spacing.borderWidth)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
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

    // MARK: - Styling

    private var foregroundColor: Color {
        switch (style, tone) {
        case (.primary, .standard):
            theme.primaryFillForeground
        case (.primary, .destructive):
            .white
        case (.ghost, .standard):
            isHovered ? theme.text : theme.textSecondary
        case (.ghost, .destructive):
            theme.error
        }
    }

    private var backgroundColor: Color {
        switch (style, tone) {
        case (.primary, .standard):
            isHovered ? theme.primaryFill.opacity(0.88) : theme.primaryFill
        case (.primary, .destructive):
            isHovered ? theme.error.opacity(0.88) : theme.error
        case (.ghost, .standard):
            isHovered ? theme.hover : .clear
        case (.ghost, .destructive):
            isHovered ? theme.errorSubtle : .clear
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            .clear
        case .ghost:
            .clear
        }
    }
}

// MARK: - Style

public extension ActionButton {
    enum Style: Sendable {
        case primary
        case ghost
    }

    enum Tone: Sendable {
        case standard
        case destructive
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: Spacing.space4) {
        ActionButton("Add Repository", icon: "folder", style: .primary) {}
        ActionButton("Cancel", style: .ghost) {}
        ActionButton("Delete", icon: "trash", style: .ghost, tone: .destructive) {}
        ActionButton("Loading", style: .primary, isLoading: true) {}
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
