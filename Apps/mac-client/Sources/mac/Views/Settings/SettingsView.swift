// SettingsView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI

struct SettingsView: View {
    @Environment(\.devysTheme) private var theme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SETTINGS")
                        .font(DevysTypography.xl)
                        .tracking(2)
                        .foregroundStyle(theme.text)
                    
                    TerminalDivider()
                }
                
                AppearanceSettingsSection()
                
                TerminalDivider()
                
                ExplorerSettingsSection()
                
                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.base)
    }
}

// MARK: - Appearance Settings Section

struct AppearanceSettingsSection: View {
    @Environment(\.devysTheme) private var theme
    @Environment(AppSettings.self) private var appSettings
    
    var body: some View {
        SettingsSection(title: "APPEARANCE") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("accent_color")
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)
                    
                    Text("Choose your accent color for highlights and focus states")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                    
                    HStack(spacing: 12) {
                        ForEach(AccentColor.allCases, id: \.self) { accent in
                            AccentColorButton(
                                accent: accent,
                                isSelected: appSettings.appearance.accentColor == accent.rawValue
                            ) {
                                appSettings.appearance.accentColor = accent.rawValue
                            }
                        }
                    }
                }
                
                TerminalDivider()
                
                SettingsToggle(
                    title: "dark_mode",
                    description: "Use dark theme for terminal aesthetic",
                    isOn: Binding(
                        get: { appSettings.appearance.isDarkMode },
                        set: { appSettings.appearance.isDarkMode = $0 }
                    )
                )
            }
        }
    }
}

// MARK: - Accent Color Button

struct AccentColorButton: View {
    @Environment(\.devysTheme) private var theme
    
    let accent: AccentColor
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(accent.color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? theme.text : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: isSelected ? accent.color.opacity(0.5) : .clear,
                        radius: 4
                    )
                
                Text(accent.displayName.lowercased())
                    .font(DevysTypography.xs)
                    .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .fill(isSelected ? theme.elevated : (isHovered ? theme.hover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings Section Container

struct SettingsSection<Content: View>: View {
    @Environment(\.devysTheme) private var theme
    
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(DevysTypography.heading)
                .tracking(DevysTypography.headerTracking)
                .foregroundStyle(theme.textSecondary)
            
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusMd)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusMd)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
        }
    }
}

// MARK: - Explorer Settings Section

struct ExplorerSettingsSection: View {
    @Environment(\.devysTheme) private var theme
    @Environment(AppSettings.self) private var appSettings

    @State private var excludePatterns: String = ""
    @State private var patterns: Set<String> = []

    private var showDotfilesBinding: Binding<Bool> {
        Binding(
            get: { appSettings.explorer.showDotfiles },
            set: { newValue in
                appSettings.explorer.showDotfiles = newValue
            }
        )
    }
    
    var body: some View {
        SettingsSection(title: "FILE_EXPLORER") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsToggle(
                    title: "show_hidden_files",
                    description: "Show files and folders that start with a dot",
                    isOn: showDotfilesBinding
                )
                
                TerminalDivider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("exclude_patterns")
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)
                    
                    Text("Files matching these patterns will be hidden")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(patterns).sorted(), id: \.self) { pattern in
                            HStack(spacing: 8) {
                                Text("├──")
                                    .font(DevysTypography.sm)
                                    .foregroundStyle(theme.textTertiary)
                                
                                Text(pattern)
                                    .font(DevysTypography.sm)
                                    .foregroundStyle(theme.textSecondary)
                                
                                Spacer()
                                
                                Button {
                                    removePattern(pattern)
                                } label: {
                                    Text("[×]")
                                        .font(DevysTypography.xs)
                                        .foregroundStyle(theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text("$")
                            .font(DevysTypography.sm)
                            .foregroundStyle(theme.textTertiary)
                        
                        TextField("add_pattern", text: $excludePatterns)
                            .textFieldStyle(.plain)
                            .font(DevysTypography.sm)
                            .onSubmit {
                                addPattern()
                            }
                        
                        if !excludePatterns.isEmpty {
                            Button {
                                addPattern()
                            } label: {
                                Text("[add]")
                                    .font(DevysTypography.xs)
                                    .foregroundStyle(theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(theme.elevated)
                    .cornerRadius(DevysSpacing.radiusSm)
                    
                    Button {
                        resetExcludePatterns()
                    } label: {
                        Text("> reset_to_defaults")
                            .font(DevysTypography.xs)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if patterns.isEmpty {
                patterns = appSettings.explorer.excludePatterns
            }
        }
        .onChange(of: appSettings.explorer.excludePatterns) { _, newValue in
            patterns = newValue
        }
    }
    
    private func addPattern() {
        let pattern = excludePatterns.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        
        patterns.insert(pattern)
        appSettings.explorer.excludePatterns = patterns
        excludePatterns = ""
    }
    
    private func removePattern(_ pattern: String) {
        patterns.remove(pattern)
        appSettings.explorer.excludePatterns = patterns
    }
    
    private func resetExcludePatterns() {
        patterns = ExplorerSettings.defaultExcludePatterns
        appSettings.explorer.excludePatterns = patterns
    }
}
