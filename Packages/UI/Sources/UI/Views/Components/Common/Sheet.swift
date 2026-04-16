// Sheet.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Modal sheet scaffold with title bar, content area, and action bar.
///
/// Use for dialogs, confirmations, settings panels, and any modal overlay.
/// Primary and secondary actions are optional — omit both for an informational sheet.
public struct Sheet<Content: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let content: Content
    private let primaryAction: SheetAction?
    private let secondaryAction: SheetAction?
    private let onDismiss: (() -> Void)?

    @State private var isCloseHovered = false

    public init(
        title: String,
        primaryAction: SheetAction? = nil,
        secondaryAction: SheetAction? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(title)
                    .font(Typography.heading)
                    .foregroundStyle(theme.text)

                Spacer()

                // Close button
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(Typography.micro.weight(.semibold))
                        .foregroundStyle(isCloseHovered ? theme.text : theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(
                            isCloseHovered ? theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(Animations.micro) { isCloseHovered = h }
                }
            }
            .padding(.horizontal, Spacing.space4)
            .padding(.vertical, Spacing.space3)

            // Separator
            Rectangle()
                .fill(theme.border)
                .frame(height: Spacing.borderWidth)

            // Content area
            content
                .padding(Spacing.space4)

            // Action bar (only if actions exist)
            if primaryAction != nil || secondaryAction != nil {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: Spacing.borderWidth)

                HStack(spacing: Spacing.space3) {
                    Spacer()

                    if let secondaryAction {
                        ActionButton(
                            secondaryAction.title,
                            style: .ghost,
                            action: secondaryAction.action
                        )
                    }

                    if let primaryAction {
                        ActionButton(
                            primaryAction.title,
                            style: .primary,
                            action: primaryAction.action
                        )
                    }
                }
                .padding(.horizontal, Spacing.space4)
                .padding(.vertical, Spacing.space3)
            }
        }
        .elevation(.overlay)
    }
}

// MARK: - Sheet Action

public struct SheetAction {
    public let title: String
    public let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

// MARK: - Previews

#Preview("Sheet") {
    ZStack {
        Color(hex: "#121110")
            .ignoresSafeArea()

        Sheet(
            title: "New Repository",
            primaryAction: SheetAction(title: "Create") {},
            secondaryAction: SheetAction(title: "Cancel") {},
            onDismiss: {},
            content: {
                VStack(alignment: .leading, spacing: Spacing.space3) {
                    Text("Enter the details for your new repository.")
                        .font(Typography.body)
                        .foregroundStyle(Theme(isDark: true).textSecondary)

                    TextInput("Repository name", text: .constant("my-project"))
                }
            }
        )
        .frame(width: 400)
        .padding(40)
    }
    .environment(\.theme, Theme(isDark: true))
}
