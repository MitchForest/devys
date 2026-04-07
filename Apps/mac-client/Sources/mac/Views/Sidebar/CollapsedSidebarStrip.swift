// CollapsedSidebarStrip.swift
// Devys - Collapsed sidebar showing expand affordance.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct CollapsedSidebarStrip: View {
    @Environment(\.devysTheme) private var theme

    let onExpand: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: DevysSpacing.space2) {
                Spacer()

                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isHovered ? theme.text : theme.textSecondary)

                Spacer()
            }
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            .background(isHovered ? theme.hover : theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Show Sidebar (⌘\\)")
    }
}
