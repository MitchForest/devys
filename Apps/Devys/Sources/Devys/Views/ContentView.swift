// ContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Bonsplit
import DevysUI

// MARK: - Theme Manager

@MainActor
@Observable
final class ThemeManager {
    var isDarkMode: Bool = false  // Default to light mode
    
    var colorScheme: ColorScheme {
        isDarkMode ? .dark : .light
    }
    
    var nsAppearance: NSAppearance? {
        NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
    }
    
    func toggle() {
        isDarkMode.toggle()
        NSApp.appearance = nsAppearance
    }
    
    func applyAppearance() {
        NSApp.appearance = nsAppearance
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var controller = BonsplitController(
        configuration: BonsplitConfiguration(
            allowSplits: true,
            allowCloseTabs: true,
            allowCloseLastPane: false,
            allowTabReordering: true,
            allowCrossPaneTabMove: true,
            autoCloseEmptyPanes: false,
            contentViewLifecycle: .keepAllAlive,
            newTabPosition: .current,
            appearance: .init(
                tabBarHeight: 36,
                tabMinWidth: 100,
                tabMaxWidth: 200,
                tabSpacing: 0,
                minimumPaneWidth: 200,
                minimumPaneHeight: 150,
                showSplitButtons: false
            )
        )
    )
    
    @State private var tabContents: [TabID: TabContent] = [:]
    @State private var hoveredSidebarItem: SidebarItem?
    @State private var hasInitialized = false
    @State private var themeManager = ThemeManager()
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            workspace
        }
        .background(surfaceColor) // ONE background for entire shell
        .preferredColorScheme(themeManager.colorScheme)
        .onAppear {
            if !hasInitialized {
                hasInitialized = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setupInitialTab()
                }
            }
        }
    }
    
    // MARK: - Theme Colors
    // Principle: Sidebar + Tab bar = surface, Content = base
    // Borders are subtle, separation through background color
    
    /// Main content background
    private var baseColor: Color {
        themeManager.isDarkMode ? Color(hex: "#1C1C1E") : Color(hex: "#FFFFFF")
    }
    
    /// Sidebar, tab bar, cards - unified surface
    private var surfaceColor: Color {
        themeManager.isDarkMode ? Color(hex: "#2C2C2E") : Color(hex: "#F5F5F7")
    }
    
    /// Hover states
    private var elevatedColor: Color {
        themeManager.isDarkMode ? Color(hex: "#3A3A3C") : Color(hex: "#EBEBEB")
    }
    
    /// Borders - barely visible
    private var borderSubtle: Color {
        themeManager.isDarkMode ? Color(hex: "#3A3A3C") : Color(hex: "#E8E8E8")
    }
    
    /// Text colors
    private var textPrimary: Color {
        themeManager.isDarkMode ? Color(hex: "#FFFFFF") : Color(hex: "#1C1C1E")
    }
    
    private var textSecondary: Color {
        themeManager.isDarkMode ? Color(hex: "#8E8E93") : Color(hex: "#6E6E73")
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        VStack(spacing: 0) {
            // New chat at top
            sidebarButton(.newChat)
                .padding(.vertical, DevysSpacing.space3)
            
            // Main actions
            VStack(spacing: DevysSpacing.space1) {
                sidebarButton(.files)
                sidebarButton(.search)
                sidebarButton(.git)
            }
            .padding(.vertical, DevysSpacing.space3)
            
            Spacer()
            
            // Bottom actions
            VStack(spacing: DevysSpacing.space1) {
                sidebarButton(.terminal)
                themeToggle
                sidebarButton(.settings)
            }
            .padding(.vertical, DevysSpacing.space3)
        }
        .frame(width: DevysSpacing.sidebarCollapsed)
        // No background needed - inherits from parent surface
    }
    
    private var themeToggle: some View {
        Button {
            withAnimation(DevysAnimation.default) {
                themeManager.toggle()
            }
        } label: {
            Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(
                    hoveredSidebarItem == .theme ? Color.primary : Color.secondary
                )
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .fill(hoveredSidebarItem == .theme ? elevatedColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(DevysAnimation.hover) {
                hoveredSidebarItem = isHovered ? .theme : nil
            }
        }
        .help(themeManager.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
    
    private func sidebarButton(_ item: SidebarItem) -> some View {
        Button {
            handleSidebarAction(item)
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(
                    hoveredSidebarItem == item ? Color.primary : Color.secondary
                )
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .fill(hoveredSidebarItem == item ? elevatedColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(DevysAnimation.hover) {
                hoveredSidebarItem = isHovered ? item : nil
            }
        }
        .help(item.tooltip)
    }
    
    // MARK: - Workspace
    
    private var workspace: some View {
        BonsplitView(
            controller: controller,
            content: { tab, paneId in
                TabContentView(
                    tab: tab,
                    content: tabContents[tab.id],
                    isFocused: controller.focusedPaneId == paneId,
                    baseColor: baseColor
                ) {
                    controller.focusPane(paneId)
                }
            },
            emptyPane: { paneId in
                EmptyPaneView(baseColor: baseColor) {
                    createTab(in: paneId, content: .welcome)
                }
            }
        )
        // NO background here - let tab bar inherit surface from parent
    }
    
    // MARK: - Actions
    
    private func setupInitialTab() {
        // Only create if no tabs exist
        guard controller.allTabIds.isEmpty else { return }
        
        if let tabId = controller.createTab(title: "Welcome", icon: "house") {
            tabContents[tabId] = .welcome
        }
    }
    
    private func createTab(in paneId: PaneID, content: TabContent) {
        if let tabId = controller.createTab(
            title: content.title,
            icon: content.icon,
            inPane: paneId
        ) {
            tabContents[tabId] = content
        }
    }
    
    private func handleSidebarAction(_ item: SidebarItem) {
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }
        
        switch item {
        case .theme:
            break
        case .newChat:
            createTab(in: paneId, content: .chat)
        case .files:
            createTab(in: paneId, content: .files)
        case .search:
            createTab(in: paneId, content: .search)
        case .git:
            createTab(in: paneId, content: .git)
        case .terminal:
            createTab(in: paneId, content: .terminal)
        case .settings:
            createTab(in: paneId, content: .settings)
        }
    }
}

// MARK: - Sidebar Items

private enum SidebarItem: CaseIterable {
    case newChat
    case files
    case search
    case git
    case terminal
    case theme
    case settings
    
    var icon: String {
        switch self {
        case .newChat: return "plus"
        case .files: return "folder"
        case .search: return "magnifyingglass"
        case .git: return "arrow.triangle.branch"
        case .terminal: return "terminal"
        case .theme: return "moon.fill"
        case .settings: return "gearshape"
        }
    }
    
    var tooltip: String {
        switch self {
        case .newChat: return "New Chat - Start AI conversation (Cmd+N)"
        case .files: return "Files - Open file browser"
        case .search: return "Search - Find in project (Cmd+Shift+F)"
        case .git: return "Source Control - View git changes"
        case .terminal: return "Terminal - Open new terminal (Cmd+T)"
        case .theme: return "Toggle light/dark mode"
        case .settings: return "Settings - Configure preferences"
        }
    }
}

// MARK: - Tab Content Types

private enum TabContent {
    case welcome
    case chat
    case files
    case search
    case git
    case terminal
    case settings
    case editor(filename: String)
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .chat: return "Chat"
        case .files: return "Files"
        case .search: return "Search"
        case .git: return "Source Control"
        case .terminal: return "Terminal"
        case .settings: return "Settings"
        case .editor(let filename): return filename
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .files: return "folder"
        case .search: return "magnifyingglass"
        case .git: return "arrow.triangle.branch"
        case .terminal: return "terminal"
        case .settings: return "gearshape"
        case .editor: return "doc.text"
        }
    }
}

// MARK: - Tab Content View

private struct TabContentView: View {
    let tab: Bonsplit.Tab
    let content: TabContent?
    let isFocused: Bool
    let baseColor: Color
    let onFocus: () -> Void
    
    var body: some View {
        ZStack {
            switch content {
            case .welcome:
                WelcomeView()
            case .terminal:
                TerminalPlaceholder()
            case .files:
                PlaceholderView(icon: "folder", title: "Files", subtitle: "Open a folder to browse files")
            case .search:
                PlaceholderView(icon: "magnifyingglass", title: "Search", subtitle: "Search across your project")
            case .git:
                PlaceholderView(icon: "arrow.triangle.branch", title: "Source Control", subtitle: "No repository open")
            case .chat:
                PlaceholderView(icon: "bubble.left.and.bubble.right", title: "Chat", subtitle: "Start a conversation with AI")
            case .settings:
                PlaceholderView(icon: "gearshape", title: "Settings", subtitle: "Configure Devys preferences")
            case .editor(let filename):
                PlaceholderView(icon: "doc.text", title: filename, subtitle: "Editor coming soon")
            case .none:
                PlaceholderView(icon: "doc", title: tab.title, subtitle: "")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(baseColor) // Content area gets base color
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
    }
}

// MARK: - Welcome View

private struct WelcomeView: View {
    var body: some View {
        VStack(spacing: DevysSpacing.space6) {
            Spacer()
            
            Image(systemName: "d.square.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: DevysSpacing.space2) {
                Text("Devys")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("AI-Native Development Canvas")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(spacing: DevysSpacing.space2) {
                QuickAction(icon: "folder.badge.plus", label: "Open Folder", shortcut: "O")
                QuickAction(icon: "doc.badge.plus", label: "New File", shortcut: "N")
                QuickAction(icon: "terminal", label: "New Terminal", shortcut: "T")
            }
            .padding(.bottom, DevysSpacing.space12)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickAction: View {
    let icon: String
    let label: String
    let shortcut: String
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: DevysSpacing.space3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text("\u{2318}\(shortcut)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DevysSpacing.space4)
        .padding(.vertical, DevysSpacing.space2)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color(nsColor: .controlBackgroundColor))
        )
        .onHover { hovering in
            withAnimation(DevysAnimation.hover) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Empty Pane View

private struct EmptyPaneView: View {
    let baseColor: Color
    let onCreateTab: () -> Void
    
    var body: some View {
        VStack(spacing: DevysSpacing.space4) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            
            Text("No tabs open")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Button {
                onCreateTab()
            } label: {
                Text("New Tab")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(baseColor)
    }
}

// MARK: - Placeholder Views

private struct TerminalPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DevysSpacing.space2) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                Text("zsh")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Text("~/projects/devys")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                
                Spacer()
            }
            .padding(.horizontal, DevysSpacing.space3)
            .padding(.vertical, DevysSpacing.space2)
            .background(Color(nsColor: .controlBackgroundColor))
            
            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                    TerminalLine(prompt: true, text: "swift build")
                    TerminalLine(prompt: false, text: "Building for debugging...")
                    TerminalLine(prompt: false, text: "Build complete!")
                    TerminalLine(prompt: true, text: "")
                }
                .padding(DevysSpacing.space3)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct TerminalLine: View {
    let prompt: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: DevysSpacing.space2) {
            if prompt {
                Text(">")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.blue)
            }
            
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
            
            if prompt && text.isEmpty {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 16)
                    .opacity(0.8)
            }
        }
    }
}

private struct PlaceholderView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: DevysSpacing.space3) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
