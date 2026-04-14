// SettingsView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import Workspace
import UI

struct SettingsView: View {
    @Environment(\.devysTheme) private var theme
    let repositoryRootURL: URL?
    let repositoryDisplayName: String?

    init(repositoryRootURL: URL? = nil, repositoryDisplayName: String? = nil) {
        self.repositoryRootURL = repositoryRootURL
        self.repositoryDisplayName = repositoryDisplayName
    }

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
                
                ShellSettingsSection()

                TerminalDivider()

                RestoreSettingsSection()

                TerminalDivider()

                NotificationSettingsSection()

                TerminalDivider()

                AppearanceSettingsSection()
                
                TerminalDivider()
                
                ExplorerSettingsSection()

                TerminalDivider()

                ShortcutSettingsSection()

                if let repositoryRootURL {
                    TerminalDivider()

                    RepositorySettingsSection(
                        repositoryRootURL: repositoryRootURL,
                        repositoryDisplayName: repositoryDisplayName
                    )
                }
                
                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.base)
    }
}

// MARK: - Shell Settings Section

struct ShellSettingsSection: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        SettingsSection(title: "SHELL") {
            SettingsTextFieldRow(
                title: "default_external_editor_bundle_id",
                description: "Bundle identifier used when opening a workspace in an external editor",
                placeholder: "com.microsoft.VSCode",
                text: Binding(
                    get: { appSettings.shell.defaultExternalEditorBundleIdentifier ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        appSettings.shell.defaultExternalEditorBundleIdentifier = trimmed.isEmpty ? nil : trimmed
                    }
                )
            )
        }
    }
}

// MARK: - Restore Settings Section

struct RestoreSettingsSection: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        SettingsSection(title: "RESTORE") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsToggle(
                    title: "restore_repositories_on_launch",
                    description: "Reopen repositories from the previous Devys session when the app relaunches",
                    isOn: Binding(
                        get: { appSettings.restore.restoreRepositoriesOnLaunch },
                        set: { appSettings.restore.restoreRepositoriesOnLaunch = $0 }
                    )
                )

                SettingsToggle(
                    title: "restore_selected_workspace",
                    description: "Return each window to the last selected workspace when repository restore is enabled",
                    isOn: Binding(
                        get: { appSettings.restore.restoreSelectedWorkspace },
                        set: { appSettings.restore.restoreSelectedWorkspace = $0 }
                    )
                )

                SettingsToggle(
                    title: "restore_workspace_layout_and_tabs",
                    description: "Rebuild the last split layout, editor tabs, and diff tabs for restored workspaces",
                    isOn: Binding(
                        get: { appSettings.restore.restoreWorkspaceLayoutAndTabs },
                        set: { appSettings.restore.restoreWorkspaceLayoutAndTabs = $0 }
                    )
                )

                SettingsToggle(
                    title: "restore_terminal_sessions",
                    description: "Reconnect persistent terminals and staged commands for restored workspaces",
                    isOn: Binding(
                        get: { appSettings.restore.restoreTerminalSessions },
                        set: { appSettings.restore.restoreTerminalSessions = $0 }
                    )
                )

                SettingsToggle(
                    title: "restore_agent_sessions",
                    description: "Reopen persisted Agents tabs and attempt ACP session restore when supported",
                    isOn: Binding(
                        get: { appSettings.restore.restoreAgentSessions },
                        set: { appSettings.restore.restoreAgentSessions = $0 }
                    )
                )
            }
        }
    }
}

// MARK: - Notification Settings Section

struct NotificationSettingsSection: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        SettingsSection(title: "NOTIFICATIONS") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsToggle(
                    title: "terminal_activity",
                    description: "Show unread terminal attention and shell bell notifications in workspace badges",
                    isOn: Binding(
                        get: { appSettings.notifications.terminalActivity },
                        set: { appSettings.notifications.terminalActivity = $0 }
                    )
                )

                SettingsToggle(
                    title: "agent_activity",
                    description:
                        "Show agent waiting or completed notifications for each workspace " +
                        "when the active launcher supports it",
                    isOn: Binding(
                        get: { appSettings.notifications.agentActivity },
                        set: { appSettings.notifications.agentActivity = $0 }
                    )
                )
            }
        }
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

struct SettingsTextFieldRow: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let description: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DevysTypography.label)
                .foregroundStyle(theme.text)

            Text(description)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
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
                                    .foregroundStyle(theme.visibleAccent)
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

// MARK: - Shortcut Settings Section

struct ShortcutSettingsSection: View {
    @Environment(\.devysTheme) private var theme
    @Environment(AppSettings.self) private var appSettings

    @State private var editingAction: WorkspaceShellShortcutAction?

    private var conflicts: WorkspaceShellShortcutConflictSet {
        detectWorkspaceShellShortcutConflicts(in: appSettings.shortcuts)
    }

    var body: some View {
        SettingsSection(title: "SHORTCUTS") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Editable bindings for the workspace shell command plane.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                if conflicts.hasConflicts {
                    Text("Resolve duplicate or reserved bindings before relying on these shortcuts.")
                        .font(DevysTypography.xs)
                        .foregroundStyle(.red)
                }

                ForEach(WorkspaceShellShortcutAction.allCases, id: \.self) { action in
                    ShortcutBindingRow(
                        action: action,
                        binding: appSettings.shortcuts.binding(for: action),
                        conflictMessages: conflicts.messages(for: action),
                        onEdit: {
                            editingAction = action
                        },
                        onRestoreDefault: {
                            restoreDefaultShortcut(for: action)
                        }
                    )
                }

                Button("Restore All Defaults") {
                    restoreAllShortcutDefaults()
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(item: $editingAction) { action in
            WorkspaceShortcutCaptureSheet(
                action: action,
                currentBinding: appSettings.shortcuts.binding(for: action)
            ) { binding in
                var shortcuts = appSettings.shortcuts
                shortcuts.setBinding(binding, for: action)
                appSettings.shortcuts = shortcuts
            }
        }
    }

    private func restoreDefaultShortcut(for action: WorkspaceShellShortcutAction) {
        var shortcuts = appSettings.shortcuts
        shortcuts.setBinding(
            WorkspaceShellShortcutSettings.defaultBinding(for: action),
            for: action
        )
        appSettings.shortcuts = shortcuts
    }

    private func restoreAllShortcutDefaults() {
        var shortcuts = appSettings.shortcuts
        shortcuts.restoreDefaults()
        appSettings.shortcuts = shortcuts
    }
}

private struct ShortcutBindingRow: View {
    @Environment(\.devysTheme) private var theme

    let action: WorkspaceShellShortcutAction
    let binding: ShortcutBinding
    let conflictMessages: [String]
    let onEdit: () -> Void
    let onRestoreDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title.lowercased())
                        .font(DevysTypography.label)
                        .foregroundStyle(theme.text)

                    Text(action.description)
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                Text(binding.displayString)
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.visibleAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.elevated)
                    .cornerRadius(DevysSpacing.radiusSm)

                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)

                Button("Default", action: onRestoreDefault)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(conflictMessages, id: \.self) { message in
                Text(message)
                    .font(DevysTypography.xs)
                    .foregroundStyle(.red)
            }
        }
    }
}
