// InlineCommit.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Inline commit message area for the sidebar.
///
/// Vertical stack: TextEditor for the commit message + a primary commit button.
/// The TextEditor shows a placeholder when empty and gains an accent border on focus.
public struct InlineCommit: View {
    @Environment(\.theme) private var theme

    @Binding private var message: String
    private let onCommit: () -> Void
    private let isCommitting: Bool

    @FocusState private var isFocused: Bool

    public init(
        message: Binding<String>,
        isCommitting: Bool = false,
        onCommit: @escaping () -> Void
    ) {
        self._message = message
        self.isCommitting = isCommitting
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(spacing: Spacing.space2) {
            // MARK: - Message Editor

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 36, maxHeight: 72)
                    .padding(.horizontal, Spacing.space1)
                    .padding(.vertical, Spacing.space1)

                if message.isEmpty {
                    Text("Commit message...")
                        .font(Typography.body)
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, Spacing.space1 + 5)
                        .padding(.vertical, Spacing.space1 + 1)
                        .allowsHitTesting(false)
                }
            }
            .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .strokeBorder(
                        isFocused ? theme.accent : theme.border,
                        lineWidth: Spacing.borderWidth
                    )
            )
            .animation(Animations.micro, value: isFocused)

            // MARK: - Commit Button

            ActionButton("Commit", icon: "checkmark", style: .primary, isLoading: isCommitting, action: onCommit)
                .frame(maxWidth: .infinity)
        }
        .padding(Spacing.space3)
        .background(theme.card)
    }
}

// MARK: - Previews

#Preview("Inline Commit") {
    struct Demo: View {
        @State var message = ""
        var body: some View {
            VStack(spacing: Spacing.space4) {
                InlineCommit(message: $message) {}
                InlineCommit(message: .constant("Fix login redirect bug"), isCommitting: true) {}
            }
            .frame(width: 280)
            .background(Color(hex: "#121110"))
            .environment(\.theme, Theme(isDark: true))
        }
    }
    return Demo()
}
