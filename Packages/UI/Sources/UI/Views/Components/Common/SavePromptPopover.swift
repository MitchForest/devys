// SavePromptPopover.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Compact dirty-file save prompt.
///
/// Displays a message with the file name and three action buttons:
/// Cancel (ghost), Don't Save (secondary), and Save (primary).
public struct SavePromptPopover: View {
    @Environment(\.theme) private var theme

    private let fileName: String
    private let onSave: () -> Void
    private let onDontSave: () -> Void
    private let onCancel: () -> Void

    public init(
        fileName: String,
        onSave: @escaping () -> Void,
        onDontSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.fileName = fileName
        self.onSave = onSave
        self.onDontSave = onDontSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            // MARK: - Message

            Text("Save changes to \(fileName)?")
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(2)

            // MARK: - Button Row

            HStack(spacing: Spacing.space2) {
                ActionButton("Cancel", style: .ghost, action: onCancel)
                Spacer()
                ActionButton(
                    "Don't Save",
                    style: .ghost,
                    tone: .destructive,
                    action: onDontSave
                )
                ActionButton("Save", style: .primary, action: onSave)
            }
        }
        .padding(Spacing.space4)
        .frame(width: 280)
        .elevation(.popover)
    }
}

// MARK: - Previews

#Preview("Save Prompt") {
    VStack(spacing: Spacing.space6) {
        SavePromptPopover(
            fileName: "ContentView.swift",
            onSave: {},
            onDontSave: {},
            onCancel: {}
        )

        SavePromptPopover(
            fileName: "really-long-filename-that-might-wrap.tsx",
            onSave: {},
            onDontSave: {},
            onCancel: {}
        )
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
