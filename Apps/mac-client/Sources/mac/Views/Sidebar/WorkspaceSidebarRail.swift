// WorkspaceSidebarRail.swift
// Devys - Vertical icon rail for workspace sidebar mode switching.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct WorkspaceSidebarRail: View {
    @Environment(\.devysTheme) private var theme

    let activeMode: WorkspaceSidebarMode?
    let onSelectMode: (WorkspaceSidebarMode) -> Void

    var body: some View {
        VStack(spacing: DevysSpacing.space1) {
            ForEach(WorkspaceSidebarMode.allCases, id: \.self) { mode in
                RailIconButton(
                    mode: mode,
                    isActive: activeMode == mode
                ) {
                    onSelectMode(mode)
                }
            }

            Spacer()
        }
        .padding(.vertical, DevysSpacing.space2)
        .frame(width: DevysSpacing.sidebarCollapsed)
        .frame(maxHeight: .infinity)
        .background(theme.surface)
    }
}

private struct RailIconButton: View {
    @Environment(\.devysTheme) private var theme

    let mode: WorkspaceSidebarMode
    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? theme.accent : (isHovered ? theme.text : theme.textSecondary))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .fill(isActive ? theme.active : (isHovered ? theme.hover : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(mode.title)
    }
}

private extension WorkspaceSidebarMode {
    var systemImage: String {
        switch self {
        case .files:
            "folder"
        case .changes:
            "arrow.triangle.branch"
        case .ports:
            "point.3.connected.trianglepath.dotted"
        }
    }

    var title: String {
        switch self {
        case .files:
            "Files"
        case .changes:
            "Changes"
        case .ports:
            "Ports"
        }
    }
}
