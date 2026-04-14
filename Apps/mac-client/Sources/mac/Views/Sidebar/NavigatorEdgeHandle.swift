// NavigatorEdgeHandle.swift
// Devys - Edge handle for toggling the navigator sidebar.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// A thin left-edge toggle target that stays clickable whether the navigator is
/// shown or hidden, without reserving layout width when hidden.
struct NavigatorEdgeHandle: View {
    @Environment(\.devysTheme) private var theme

    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(indicatorColor)
                        .frame(width: isHovered || isExpanded ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isExpanded ? "Hide Navigator (⌘0)" : "Show Navigator (⌘0)")
    }

    private var indicatorColor: Color {
        if isHovered {
            return theme.visibleAccent.opacity(0.65)
        }
        if isExpanded {
            return theme.border
        }
        return theme.borderSubtle.opacity(0.9)
    }
}
