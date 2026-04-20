// FormField.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Form field wrapper with a tertiary micro-weight label above the control.
///
/// Use inside sheets and inspector panels for labelled inputs. Pairs with
/// `TextInput`, `SecureInput`, `TextEditorField`, `SegmentedControl`, and
/// any other single-purpose control that needs a caption above it.
public struct FormField<Content: View>: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let content: Content

    public init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            Text(title)
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
            content
        }
    }
}

#Preview("Form Fields") {
    VStack(alignment: .leading, spacing: Spacing.space3) {
        FormField("Repository") {
            TextInput("devys", text: .constant("devys"), icon: "folder")
        }
        FormField("Port") {
            TextInput("22", text: .constant("22"))
        }
    }
    .frame(width: 320)
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
