// WorkspaceShortcutCaptureSheet.swift
// Modal recorder for workspace shell shortcuts.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI
import Workspace

struct WorkspaceShortcutCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devysTheme) private var theme

    let action: WorkspaceShellShortcutAction
    let onSave: (ShortcutBinding) -> Void

    @State private var draftBinding: ShortcutBinding
    @State private var keyMonitor: Any?
    @State private var errorMessage: String?

    init(
        action: WorkspaceShellShortcutAction,
        currentBinding: ShortcutBinding,
        onSave: @escaping (ShortcutBinding) -> Void
    ) {
        self.action = action
        self.onSave = onSave
        _draftBinding = State(initialValue: currentBinding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(action.title)
                    .font(DevysTypography.xl)
                    .foregroundStyle(theme.text)

                Text("Press the shortcut you want to use. Include at least one modifier key.")
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("CURRENT")
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.textSecondary)

                Text(draftBinding.displayString)
                    .font(DevysTypography.xl)
                    .foregroundStyle(theme.visibleAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(theme.surface)
                    .cornerRadius(DevysSpacing.radiusMd)
                    .overlay(
                        RoundedRectangle(cornerRadius: DevysSpacing.radiusMd)
                            .strokeBorder(theme.borderSubtle, lineWidth: 1)
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DevysTypography.xs)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(draftBinding)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 260)
        .background(theme.base)
        .onAppear {
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                dismiss()
                return nil
            }

            guard let binding = ShortcutBinding.from(event: event) else {
                errorMessage = "Use at least one modifier and a supported key."
                NSSound.beep()
                return nil
            }

            draftBinding = binding
            errorMessage = nil
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
