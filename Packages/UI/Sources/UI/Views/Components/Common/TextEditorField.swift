// TextEditorField.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Multi-line text editor with the same chrome as `TextInput`.
///
/// Replaces ad-hoc compositions of padding + background + border + clipShape
/// scattered across feature code. Use this whenever you need a multi-line,
/// monospaced or plain text editor that matches the design system.
public struct TextEditorField: View {
    @Environment(\.theme) private var theme

    @Binding private var text: String
    private let minHeight: CGFloat
    private let isMonospaced: Bool
    private let background: InputBackground

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        minHeight: CGFloat = 120,
        isMonospaced: Bool = false,
        background: InputBackground = .card
    ) {
        self._text = text
        self.minHeight = minHeight
        self.isMonospaced = isMonospaced
        self.background = background
    }

    public var body: some View {
        TextEditor(text: $text)
            .font(isMonospaced ? .system(.body, design: .monospaced) : Typography.body)
            .foregroundStyle(theme.text)
            .scrollContentBackground(.hidden)
            .padding(Spacing.space2)
            .frame(minHeight: minHeight)
            .focused($isFocused)
            .inputChrome(background, isFocused: isFocused)
    }
}
