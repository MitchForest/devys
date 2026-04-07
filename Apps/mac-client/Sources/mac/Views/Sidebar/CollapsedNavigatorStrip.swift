// CollapsedNavigatorStrip.swift
// Devys - Collapsed navigator showing expand affordance.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct CollapsedNavigatorStrip: View {
    @Environment(\.devysTheme) private var theme

    let repositoryCount: Int
    let onExpand: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onExpand) {
            VStack(spacing: DevysSpacing.space2) {
                Spacer()

                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isHovered ? theme.text : theme.textSecondary)

                if repositoryCount > 1 {
                    Text("\(repositoryCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(theme.elevated)
                        )
                }

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
        .help("Show Navigator (⌘0)")
    }
}
