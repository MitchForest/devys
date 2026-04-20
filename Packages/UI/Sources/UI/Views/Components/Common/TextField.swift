// TextInput.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

public enum InputBackground: Sendable {
    case base
    case card
    case overlay
}

private struct InputChromeModifier: ViewModifier {
    @Environment(\.theme) private var theme

    let background: InputBackground
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .strokeBorder(
                        isFocused ? theme.borderFocus : theme.border,
                        lineWidth: Spacing.borderWidth
                    )
            )
            .animation(Animations.micro, value: isFocused)
    }

    private var backgroundColor: Color {
        switch background {
        case .base:
            theme.base
        case .card:
            theme.card
        case .overlay:
            theme.overlay
        }
    }
}

public extension View {
    func inputChrome(
        _ background: InputBackground = .card,
        isFocused: Bool = false
    ) -> some View {
        modifier(InputChromeModifier(background: background, isFocused: isFocused))
    }
}

/// Text input with recessed background and focus ring.
public struct TextInput: View {
    @Environment(\.theme) private var theme

    private let placeholder: String
    @Binding private var text: String
    private let icon: String?

    @FocusState private var isFocused: Bool

    public init(
        _ placeholder: String,
        text: Binding<String>,
        icon: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            if let icon {
                Image(systemName: icon)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(isFocused ? theme.accent : theme.textTertiary)
                    .frame(width: 16)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .focused($isFocused)
        }
        .padding(.horizontal, Spacing.space2)
        .padding(.vertical, Spacing.space2)
        .inputChrome(.card, isFocused: isFocused)
    }
}

/// Secure text input that mirrors `TextInput` chrome for passwords and passphrases.
public struct SecureInput: View {
    @Environment(\.theme) private var theme

    private let placeholder: String
    @Binding private var text: String
    private let icon: String?

    @FocusState private var isFocused: Bool

    public init(
        _ placeholder: String,
        text: Binding<String>,
        icon: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            if let icon {
                Image(systemName: icon)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(isFocused ? theme.accent : theme.textTertiary)
                    .frame(width: 16)
            }
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .focused($isFocused)
        }
        .padding(.horizontal, Spacing.space2)
        .padding(.vertical, Spacing.space2)
        .inputChrome(.card, isFocused: isFocused)
    }
}

/// Search-specific input with magnifying glass and clear button.
public struct SearchInput: View {
    @Environment(\.theme) private var theme

    private let placeholder: String
    @Binding private var text: String

    @FocusState private var isFocused: Bool

    public init(_ placeholder: String = "Search...", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: "magnifyingglass")
                .font(Typography.body.weight(.medium))
                .foregroundStyle(isFocused ? theme.accent : theme.textTertiary)
                .frame(width: 16)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.label)
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.space3)
        .padding(.vertical, Spacing.space2)
        .inputChrome(.card, isFocused: isFocused)
    }
}

// MARK: - Previews

#Preview("Text Fields") {
    struct Demo: View {
        @State var name = ""
        @State var search = ""
        var body: some View {
            VStack(spacing: Spacing.space4) {
                TextInput("Repository name", text: $name, icon: "folder")
                SearchInput("Search files, commands, agents...", text: $search)
            }
            .frame(width: 320)
            .padding(24)
            .background(Color(hex: "#121110"))
            .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
        }
    }
    return Demo()
}
