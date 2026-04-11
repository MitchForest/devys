// AppSettings.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var shell: ShellSettings
    public var explorer: ExplorerSettings
    public var appearance: AppearanceSettings
    public var agent: AgentSettings
    public var notifications: NotificationSettings
    public var restore: RestoreSettings
    public var shortcuts: WorkspaceShellShortcutSettings

    private enum CodingKeys: String, CodingKey {
        case shell
        case explorer
        case appearance
        case agent
        case notifications
        case restore
        case shortcuts
    }

    public init(
        shell: ShellSettings = ShellSettings(),
        explorer: ExplorerSettings = ExplorerSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        agent: AgentSettings = AgentSettings(),
        notifications: NotificationSettings = NotificationSettings(),
        restore: RestoreSettings = RestoreSettings(),
        shortcuts: WorkspaceShellShortcutSettings = WorkspaceShellShortcutSettings()
    ) {
        self.shell = shell
        self.explorer = explorer
        self.appearance = appearance
        self.agent = agent
        self.notifications = notifications
        self.restore = restore
        self.shortcuts = shortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyShell = try container.decodeIfPresent(LegacyShellSettings.self, forKey: .shell)
            ?? LegacyShellSettings()

        self.shell = legacyShell.currentSettings
        self.explorer = try container.decodeIfPresent(ExplorerSettings.self, forKey: .explorer)
            ?? ExplorerSettings()
        self.appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance)
            ?? AppearanceSettings()
        self.agent = try container.decodeIfPresent(AgentSettings.self, forKey: .agent)
            ?? AgentSettings()
        self.notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications)
            ?? NotificationSettings()
        self.restore = try container.decodeIfPresent(RestoreSettings.self, forKey: .restore)
            ?? RestoreSettings(restoreTerminalSessions: legacyShell.preserveTerminalsOnRelaunch ?? false)
        self.shortcuts = try container.decodeIfPresent(
            WorkspaceShellShortcutSettings.self,
            forKey: .shortcuts
        ) ?? WorkspaceShellShortcutSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shell, forKey: .shell)
        try container.encode(explorer, forKey: .explorer)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(agent, forKey: .agent)
        try container.encode(notifications, forKey: .notifications)
        try container.encode(restore, forKey: .restore)
        try container.encode(shortcuts, forKey: .shortcuts)
    }
}

/// Central settings model for the Devys application.
///
/// This is the single source of truth for all user preferences.
/// Settings are automatically persisted to UserDefaults on change.
///
/// Usage:
/// ```swift
/// @Environment(AppSettings.self) var settings
/// ```
@MainActor
@Observable
public final class AppSettings {
    // MARK: - Settings Categories

    /// Shell-level settings.
    public var shell: ShellSettings {
        didSet { save() }
    }
    
    /// File explorer settings
    public var explorer: ExplorerSettings {
        didSet { save() }
    }
    
    /// Appearance settings (theme, fonts, etc.)
    public var appearance: AppearanceSettings {
        didSet { save() }
    }
    
    /// Agent/chat settings
    public var agent: AgentSettings {
        didSet { save() }
    }

    /// Workspace notification preferences.
    public var notifications: NotificationSettings {
        didSet { save() }
    }

    /// Session and workspace restore preferences.
    public var restore: RestoreSettings {
        didSet { save() }
    }

    /// User-editable workspace shell shortcuts.
    public var shortcuts: WorkspaceShellShortcutSettings {
        didSet { save() }
    }
    
    // MARK: - Persistence

    private let persistenceService: SettingsPersistenceService
    
    // MARK: - Initialization
    
    public init(persistenceService: SettingsPersistenceService = UserDefaultsSettingsPersistenceService()) {
        self.persistenceService = persistenceService
        let globalSettings = persistenceService.loadGlobalSettings()
        self.shell = globalSettings.shell
        self.explorer = globalSettings.explorer
        self.appearance = globalSettings.appearance
        self.agent = globalSettings.agent
        self.notifications = globalSettings.notifications
        self.restore = globalSettings.restore
        self.shortcuts = globalSettings.shortcuts
    }
    
    private func save() {
        persistenceService.saveGlobalSettings(
            GlobalSettings(
                shell: shell,
                explorer: explorer,
                appearance: appearance,
                agent: agent,
                notifications: notifications,
                restore: restore,
                shortcuts: shortcuts
            )
        )
    }
    
    // MARK: - Reset
    
    /// Resets all settings to defaults
    public func resetToDefaults() {
        shell = ShellSettings()
        explorer = ExplorerSettings()
        appearance = AppearanceSettings()
        agent = AgentSettings()
        notifications = NotificationSettings()
        restore = RestoreSettings()
        shortcuts = WorkspaceShellShortcutSettings()
    }
}

// MARK: - Shell Settings

/// Settings for shell-wide behavior.
public struct ShellSettings: Codable, Equatable, Sendable {
    /// Optional bundle identifier for the preferred external editor.
    public var defaultExternalEditorBundleIdentifier: String?

    public init(
        defaultExternalEditorBundleIdentifier: String? = nil
    ) {
        self.defaultExternalEditorBundleIdentifier = defaultExternalEditorBundleIdentifier
    }
}

private struct LegacyShellSettings: Codable, Equatable, Sendable {
    var defaultExternalEditorBundleIdentifier: String?
    var preserveTerminalsOnRelaunch: Bool?

    init(
        defaultExternalEditorBundleIdentifier: String? = nil,
        preserveTerminalsOnRelaunch: Bool? = nil
    ) {
        self.defaultExternalEditorBundleIdentifier = defaultExternalEditorBundleIdentifier
        self.preserveTerminalsOnRelaunch = preserveTerminalsOnRelaunch
    }

    var currentSettings: ShellSettings {
        ShellSettings(defaultExternalEditorBundleIdentifier: defaultExternalEditorBundleIdentifier)
    }
}

// MARK: - Notification Settings

public struct NotificationSettings: Codable, Equatable, Sendable {
    public var terminalActivity: Bool
    public var agentActivity: Bool

    public init(
        terminalActivity: Bool = true,
        agentActivity: Bool = true
    ) {
        self.terminalActivity = terminalActivity
        self.agentActivity = agentActivity
    }
}

// MARK: - Restore Settings

public struct RestoreSettings: Codable, Equatable, Sendable {
    public var restoreRepositoriesOnLaunch: Bool
    public var restoreSelectedWorkspace: Bool
    public var restoreWorkspaceLayoutAndTabs: Bool
    public var restoreTerminalSessions: Bool
    public var restoreAgentSessions: Bool

    private enum CodingKeys: String, CodingKey {
        case restoreRepositoriesOnLaunch
        case restoreSelectedWorkspace
        case restoreWorkspaceLayoutAndTabs
        case restoreTerminalSessions
        case restoreAgentSessions
    }

    public init(
        restoreRepositoriesOnLaunch: Bool = true,
        restoreSelectedWorkspace: Bool = true,
        restoreWorkspaceLayoutAndTabs: Bool = true,
        restoreTerminalSessions: Bool = false,
        restoreAgentSessions: Bool = true
    ) {
        self.restoreRepositoriesOnLaunch = restoreRepositoriesOnLaunch
        self.restoreSelectedWorkspace = restoreSelectedWorkspace
        self.restoreWorkspaceLayoutAndTabs = restoreWorkspaceLayoutAndTabs
        self.restoreTerminalSessions = restoreTerminalSessions
        self.restoreAgentSessions = restoreAgentSessions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restoreRepositoriesOnLaunch = try container.decodeIfPresent(
            Bool.self,
            forKey: .restoreRepositoriesOnLaunch
        ) ?? true
        restoreSelectedWorkspace = try container.decodeIfPresent(
            Bool.self,
            forKey: .restoreSelectedWorkspace
        ) ?? true
        restoreWorkspaceLayoutAndTabs = try container.decodeIfPresent(
            Bool.self,
            forKey: .restoreWorkspaceLayoutAndTabs
        ) ?? true
        restoreTerminalSessions = try container.decodeIfPresent(
            Bool.self,
            forKey: .restoreTerminalSessions
        ) ?? false
        restoreAgentSessions = try container.decodeIfPresent(
            Bool.self,
            forKey: .restoreAgentSessions
        ) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(restoreRepositoriesOnLaunch, forKey: .restoreRepositoriesOnLaunch)
        try container.encode(restoreSelectedWorkspace, forKey: .restoreSelectedWorkspace)
        try container.encode(restoreWorkspaceLayoutAndTabs, forKey: .restoreWorkspaceLayoutAndTabs)
        try container.encode(restoreTerminalSessions, forKey: .restoreTerminalSessions)
        try container.encode(restoreAgentSessions, forKey: .restoreAgentSessions)
    }
}

// MARK: - Explorer Settings

/// Settings for the file explorer sidebar.
public struct ExplorerSettings: Codable, Equatable, Sendable {
    /// Whether to show dotfiles (files/folders starting with '.')
    public var showDotfiles: Bool
    
    /// Patterns to always exclude from the file tree
    public var excludePatterns: Set<String>
    
    /// Default patterns that are hidden even when showDotfiles is true
    public static let defaultExcludePatterns: Set<String> = [
        ".DS_Store",
        ".git",
        ".svn",
        ".hg",
        "CVS",
        ".Spotlight-V100",
        ".Trashes",
        "Thumbs.db",
        "desktop.ini",
        ".idea",
        ".vscode"  // Most users don't need to see this
    ]
    
    public init(
        showDotfiles: Bool = true,
        excludePatterns: Set<String> = ExplorerSettings.defaultExcludePatterns
    ) {
        self.showDotfiles = showDotfiles
        self.excludePatterns = excludePatterns
    }
    
    /// Checks if a filename should be excluded from the file tree
    public func shouldExclude(_ filename: String) -> Bool {
        // Always exclude patterns in excludePatterns
        if excludePatterns.contains(filename) {
            return true
        }
        
        // If showDotfiles is false, exclude all dotfiles
        if !showDotfiles && filename.hasPrefix(".") {
            return true
        }
        
        return false
    }
}

// MARK: - Appearance Settings

/// Settings for visual appearance.
public struct AppearanceSettings: Codable, Equatable, Sendable {
    /// Whether dark mode is enabled (default: true for terminal aesthetic)
    public var isDarkMode: Bool
    
    /// UI font size multiplier (1.0 = default)
    public var uiFontScale: Double
    
    /// Accent color identifier (AccentColor.rawValue)
    /// Default: coral (#FF6B6B)
    public var accentColor: String
    
    public init(
        isDarkMode: Bool = true,  // Default to dark for terminal aesthetic
        uiFontScale: Double = 1.0,
        accentColor: String = "#FFFFFF"  // White/Monochrome - pure terminal look
    ) {
        self.isDarkMode = isDarkMode
        self.uiFontScale = uiFontScale
        self.accentColor = accentColor
    }
}

// MARK: - Agent Settings

/// Settings for AI agent/chat behavior.
public struct AgentSettings: Codable, Equatable, Sendable {
    /// Default harness for new chats.
    /// Stored as raw string to avoid dependency on Agents.
    /// Valid values: "claudeCode", "codex", or nil (always ask).
    public var defaultHarness: String?
    
    public init(defaultHarness: String? = nil) {
        self.defaultHarness = defaultHarness
    }
    
    /// Known harness identifiers
    public enum Harness: String, CaseIterable, Sendable {
        case claudeCode
        case codex
        
        public var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            }
        }
    }
}
