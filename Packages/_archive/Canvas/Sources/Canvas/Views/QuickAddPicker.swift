// QuickAddPicker.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// A popover for quickly adding nodes at a specific canvas location.
///
/// Shown on double-click on the canvas background. Provides a list
/// of available node types that can be created at the clicked location.
///
/// Features:
/// - Keyboard navigation (↑↓, Enter, Escape)
/// - Immediate creation on selection
struct QuickAddPicker: View {
    /// Canvas position where the node will be created (in canvas coordinates)
    let canvasPosition: CGPoint

    /// Callback when a node type is selected
    let onAddNode: (CGPoint) -> Void

    /// Callback to dismiss without selection
    let onDismiss: () -> Void

    @Environment(\.devysTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var selectedIndex: Int = 0

    /// Available node types (placeholder for now)
    private let nodeTypes: [(name: String, icon: String)] = [
        ("Node", "rectangle"),
        // Future: ("Agent", "cpu"), ("Bash", "terminal"), ("Git", "arrow.triangle.branch"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Add Node")
                    .font(DevysTypography.sm)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.text)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 4)

            // Node types
            VStack(spacing: 2) {
                ForEach(Array(nodeTypes.enumerated()), id: \.offset) { index, nodeType in
                    Button {
                        onAddNode(canvasPosition)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: nodeType.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 16)

                            Text(nodeType.name)
                                .font(DevysTypography.sm)
                                .foregroundStyle(theme.text)

                            Spacer()

                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(theme.hover)
                                )
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedIndex == index ? theme.active : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered in
                        if hovered { selectedIndex = index }
                    }
                }
            }

            Divider().padding(.vertical, 4)

            // Hints
            HStack(spacing: 12) {
                hintLabel("↑↓", "Navigate")
                hintLabel("⏎", "Add")
                hintLabel("Esc", "Cancel")
            }
        }
        .padding(12)
        .frame(width: 200)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.return) {
            onAddNode(canvasPosition)
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < nodeTypes.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            if let digit = Int(press.characters), digit >= 1, digit <= nodeTypes.count {
                onAddNode(canvasPosition)
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private func hintLabel(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundStyle(theme.textTertiary)
    }
}
