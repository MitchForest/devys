// HarnessPickerSheet.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import ChatUI
import Workspace
import UI

/// Sheet for selecting a harness when creating a new chat.
/// Shown when no default harness is configured in settings.
struct HarnessPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme
    @Environment(AppSettings.self) private var appSettings

    @State private var makeDefault = false

    let onSelect: (ChatCore.HarnessType) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(theme.accent)

                Text("Choose AI Harness")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.text)

                Text("Select which AI assistant to use for this chat")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.top, 8)

            // Harness options
            VStack(spacing: 12) {
                ForEach(HarnessType.allKnown) { harness in
                    HarnessOptionButton(harness: harness) {
                        // Save as default if checkbox is checked
                        if makeDefault {
                            appSettings.agent.defaultHarness = harness.rawValue
                        }
                        dismiss()
                        onSelect(harness)
                    }
                }
            }

            Divider()

            // Make default checkbox
            Toggle(isOn: $makeDefault) {
                Text("Make this my default harness")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            .toggleStyle(.checkbox)

            // Cancel button
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
        .padding(24)
        .frame(width: 320)
        .background(theme.surface)
    }
}

/// Button for selecting a harness option
private struct HarnessOptionButton: View {
    @Environment(\.devysTheme) private var theme

    let harness: ChatCore.HarnessType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon - use theme accent for consistency
                Image(systemName: harness.iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.accent)
                    .frame(width: 32)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(harness.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.text)

                    Text(harness == .claudeCode ? "Anthropic Claude" : "OpenAI Codex")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.elevated)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
