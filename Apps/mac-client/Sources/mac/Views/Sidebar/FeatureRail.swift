// FeatureRail.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct FeatureRail: View {
    @Environment(\.devysTheme) private var theme
    
    @Binding var activeItem: SidebarItem?
    @Binding var isDarkMode: Bool
    let onNewTerminal: () -> Void
    let onOpenSettings: () -> Void
    
    @State private var hoveredItem: SidebarItem?
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: DevysSpacing.space1) {
                    featureButton(.files)
                    featureButton(.git)
                    featureButton(.agents)
                }
                .padding(.vertical, DevysSpacing.space3)
                
                Spacer()
                
                VStack(spacing: DevysSpacing.space1) {
                    Button {
                        onNewTerminal()
                    } label: {
                        Image(systemName: "terminal")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(hoveredItem == .settings ? theme.text : theme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                                    .fill(Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("New Terminal (⌘T)")

                    themeToggle
                    featureButton(.settings)
                }
                .padding(.vertical, DevysSpacing.space3)
            }
            .frame(maxWidth: .infinity)
            
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
        .frame(width: DevysSpacing.sidebarCollapsed)
        .background(theme.surface)
    }
    
    private func featureButton(_ item: SidebarItem) -> some View {
        let isActive = activeItem == item
        
        return Button {
            handleAction(item)
        } label: {
            Image(systemName: isActive ? item.iconFilled : item.icon)
                .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                .foregroundStyle(foregroundColor(for: item, isActive: isActive))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .fill(backgroundColor(for: item, isActive: isActive))
                )
                .shadow(
                    color: isActive ? theme.accent.opacity(0.3) : .clear,
                    radius: 4,
                    x: 0,
                    y: 0
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(DevysAnimation.hover) {
                hoveredItem = hovered ? item : nil
            }
        }
        .help(item.tooltip)
    }
    
    private var themeToggle: some View {
        Button {
            withAnimation(DevysAnimation.default) {
                isDarkMode.toggle()
            }
        } label: {
            Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
    
    private func foregroundColor(for item: SidebarItem, isActive: Bool) -> Color {
        if isActive {
            return theme.accent
        } else if hoveredItem == item {
            return theme.text
        } else {
            return theme.textSecondary
        }
    }
    
    private func backgroundColor(for item: SidebarItem, isActive: Bool) -> Color {
        if isActive {
            return theme.accentMuted
        } else if hoveredItem == item {
            return theme.elevated
        } else {
            return Color.clear
        }
    }
    
    private func handleAction(_ item: SidebarItem) {
        switch item {
        case .settings:
            onOpenSettings()
        case .files, .git, .agents:
            withAnimation(.easeInOut(duration: 0.2)) {
                if activeItem == item {
                    activeItem = nil
                } else {
                    activeItem = item
                }
            }
        }
    }
}

// MARK: - Sidebar Item Enum

enum SidebarItem: CaseIterable {
    case files
    case git
    case agents
    case settings
    
    var icon: String {
        switch self {
        case .files: return "folder"
        case .git: return "arrow.triangle.branch"
        case .agents: return "cpu"
        case .settings: return "gearshape"
        }
    }
    
    var iconFilled: String {
        switch self {
        case .files: return "folder.fill"
        case .git: return "arrow.triangle.branch"
        case .agents: return "cpu.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    var tooltip: String {
        switch self {
        case .files: return "Explorer (⌘1)"
        case .git: return "Git (⌘2)"
        case .agents: return "Agents"
        case .settings: return "Settings (⌘,)"
        }
    }
}
