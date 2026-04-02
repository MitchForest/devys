// AppSettings.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

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
    
    // MARK: - Persistence

    private let persistenceService: SettingsPersistenceService
    
    // MARK: - Initialization
    
    public init(persistenceService: SettingsPersistenceService = UserDefaultsSettingsPersistenceService()) {
        self.persistenceService = persistenceService
        self.explorer = persistenceService.loadExplorerSettings()
        self.appearance = persistenceService.loadAppearanceSettings()
        self.agent = persistenceService.loadAgentSettings()
    }
    
    private func save() {
        persistenceService.saveExplorerSettings(explorer)
        persistenceService.saveAppearanceSettings(appearance)
        persistenceService.saveAgentSettings(agent)
    }
    
    // MARK: - Reset
    
    /// Resets all settings to defaults
    public func resetToDefaults() {
        explorer = ExplorerSettings()
        appearance = AppearanceSettings()
        agent = AgentSettings()
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
