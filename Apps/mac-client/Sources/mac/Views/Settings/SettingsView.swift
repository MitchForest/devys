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
            VStack(alignment: .leading, spacing: Spacing.spacious) {
                Text("Settings")
                    .font(Typography.title)
                    .foregroundStyle(theme.text)

                ShellSettingsSection()
                RestoreSettingsSection()
                NotificationSettingsSection()
                AppearanceSettingsSection()
                ExplorerSettingsSection()
                ShortcutSettingsSection()

                if let repositoryRootURL {
                    RepositorySettingsSection(
                        repositoryRootURL: repositoryRootURL,
                        repositoryDisplayName: repositoryDisplayName
                    )
                }

                Spacer()
            }
            .padding(Spacing.space8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.base)
    }
}

// MARK: - Shell Settings Section

struct ShellSettingsSection: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        SettingsSection(title: "Shell") {
            SettingsTextFieldRow(
                title: "Default external editor bundle ID",
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
        SettingsSection(title: "Restore") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsToggle(
                    title: "Restore repositories on launch",
                    description: "Reopen repositories from the previous Devys session when the app relaunches",
                    isOn: Binding(
                        get: { appSettings.restore.restoreRepositoriesOnLaunch },
                        set: { appSettings.restore.restoreRepositoriesOnLaunch = $0 }
                    )
                )

                SettingsToggle(
                    title: "Restore selected workspace",
                    description: "Return each window to the last selected workspace when repository restore is enabled",
                    isOn: Binding(
                        get: { appSettings.restore.restoreSelectedWorkspace },
                        set: { appSettings.restore.restoreSelectedWorkspace = $0 }
                    )
                )

                SettingsToggle(
                    title: "Restore workspace layout and tabs",
                    description: "Rebuild the last split layout, editor tabs, and diff tabs for restored workspaces",
                    isOn: Binding(
                        get: { appSettings.restore.restoreWorkspaceLayoutAndTabs },
                        set: { appSettings.restore.restoreWorkspaceLayoutAndTabs = $0 }
                    )
                )

                SettingsToggle(
                    title: "Restore terminal sessions",
                    description: "Reconnect persistent terminals and staged commands for restored workspaces",
                    isOn: Binding(
                        get: { appSettings.restore.restoreTerminalSessions },
                        set: { appSettings.restore.restoreTerminalSessions = $0 }
                    )
                )

                SettingsToggle(
                    title: "Restore chats",
                    description: "Reopen persisted chat tabs and attempt ACP session restore when supported",
                    isOn: Binding(
                        get: { appSettings.restore.restoreChatSessions },
                        set: { appSettings.restore.restoreChatSessions = $0 }
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
        SettingsSection(title: "Notifications") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsToggle(
                    title: "Terminal activity",
                    description: "Show unread terminal attention and shell bell notifications in workspace badges",
                    isOn: Binding(
                        get: { appSettings.notifications.terminalActivity },
                        set: { appSettings.notifications.terminalActivity = $0 }
                    )
                )

                SettingsToggle(
                    title: "Chat activity",
                    description:
                        "Show chat waiting or completed notifications for each workspace " +
                        "when the active launcher supports it",
                    isOn: Binding(
                        get: { appSettings.notifications.chatActivity },
                        set: { appSettings.notifications.chatActivity = $0 }
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

    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { appSettings.appearance.mode },
            set: { appSettings.appearance.mode = $0 }
        )
    }
    
    var body: some View {
        SettingsSection(title: "Appearance") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme")
                        .font(Typography.body)
                        .foregroundStyle(theme.text)

                    Text("Auto follows macOS appearance. Light and Dark lock the app theme.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)

                    Picker("Theme", selection: appearanceModeBinding) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Separator()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent color")
                        .font(Typography.body)
                        .foregroundStyle(theme.text)

                    Text("Choose your accent color for highlights and focus states")
                        .font(Typography.caption)
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
                                isSelected ? theme.accent : Color.clear,
                                lineWidth: 2
                            )
                    )
                
                Text(accent.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(selectionBackground, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .strokeBorder(isSelected ? theme.borderFocus : Color.clear, lineWidth: Spacing.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var selectionBackground: Color {
        if isSelected { return theme.overlay }
        if isHovered { return theme.hover }
        return .clear
    }
}

// MARK: - Settings Section Container

struct SettingsSection<Content: View>: View {
    @Environment(\.devysTheme) private var theme
    
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(theme.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.space4) {
                content()
            }
            .padding(Spacing.space4)
            .elevation(.card)
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
        VStack(alignment: .leading, spacing: Spacing.space2) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(theme.text)

            Text(description)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)

            TextInput(placeholder, text: $text)
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
        SettingsSection(title: "File Explorer") {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                SettingsToggle(
                    title: "Show hidden files",
                    description: "Show files and folders that start with a dot",
                    isOn: showDotfilesBinding
                )

                Separator()

                VStack(alignment: .leading, spacing: Spacing.space3) {
                    Text("Exclude patterns")
                        .font(Typography.body)
                        .foregroundStyle(theme.text)

                    Text("Files matching these patterns will be hidden")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)

                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        ForEach(Array(patterns).sorted(), id: \.self) { pattern in
                            HStack(spacing: Spacing.space2) {
                                Text(pattern)
                                    .font(Typography.Code.base)
                                    .foregroundStyle(theme.textSecondary)

                                Spacer()

                                Button {
                                    removePattern(pattern)
                                } label: {
                                    Icon("xmark.circle", size: .sm, color: theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, Spacing.space1)
                        }
                    }

                    HStack(spacing: Spacing.space2) {
                        TextInput("Add pattern...", text: $excludePatterns)
                            .onSubmit {
                                addPattern()
                            }

                        if !excludePatterns.isEmpty {
                            ActionButton("Add", style: .ghost) {
                                addPattern()
                            }
                            .controlSize(.small)
                        }
                    }

                    Button("Reset to defaults") {
                        resetExcludePatterns()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.error)
                    .font(Typography.caption)
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
        SettingsSection(title: "Shortcuts") {
            VStack(alignment: .leading, spacing: Spacing.space4) {
                Text("Editable bindings for the workspace shell command plane.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)

                if conflicts.hasConflicts {
                    Text("Resolve duplicate or reserved bindings before relying on these shortcuts.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.error)
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
                .buttonStyle(.plain)
                .font(Typography.label)
                .foregroundStyle(theme.textSecondary)
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
        VStack(alignment: .leading, spacing: Spacing.space2) {
            HStack(alignment: .top, spacing: Spacing.space4) {
                VStack(alignment: .leading, spacing: Spacing.space1) {
                    Text(action.title)
                        .font(Typography.body)
                        .foregroundStyle(theme.text)

                    Text(action.description)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()

                ShortcutBadge(binding.displayString)

                ActionButton("Edit", style: .ghost, action: onEdit)
                    .controlSize(.small)

                ActionButton("Default", style: .ghost, action: onRestoreDefault)
                    .controlSize(.small)
            }

            ForEach(conflictMessages, id: \.self) { message in
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(theme.error)
            }
        }
    }
}
