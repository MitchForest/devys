// EditorConfiguration.swift
// DevysEditor - Metal-accelerated code editor
//
// Configuration options for the editor.

import Foundation
import SwiftUI

// MARK: - Color Scheme

/// Editor color scheme
enum EditorColorScheme: Sendable {
    case light
    case dark
    case system
    
    /// Get the appropriate theme name for this scheme
    var themeName: String {
        switch self {
        case .light: return "github-light"
        case .dark: return "github-dark"
        case .system: return "github-dark" // Fallback
        }
    }
}

// MARK: - Editor Configuration

/// Configuration for the editor appearance and behavior.
struct EditorConfiguration: Sendable {
    /// Font name
    var fontName: String
    
    /// Font size in points
    var fontSize: CGFloat
    
    /// Color scheme (light/dark)
    var colorScheme: EditorColorScheme
    
    /// Tab width in spaces
    var tabWidth: Int
    
    /// Insert spaces for tabs
    var insertSpacesForTab: Bool
    
    /// Use DevysColors instead of theme colors
    var useDevysColors: Bool
    
    /// Theme name (derived from colorScheme)
    var themeName: String {
        colorScheme.themeName
    }
    
    init(
        fontName: String = "Menlo",
        fontSize: CGFloat = 13,
        colorScheme: EditorColorScheme = .dark,
        tabWidth: Int = 4,
        insertSpacesForTab: Bool = true,
        useDevysColors: Bool = true
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorScheme = colorScheme
        self.tabWidth = tabWidth
        self.insertSpacesForTab = insertSpacesForTab
        self.useDevysColors = useDevysColors
    }
    
    /// Default configuration (dark mode with DevysColors)
    static let `default` = EditorConfiguration()
    
}

// MARK: - Environment Key

private struct EditorConfigurationKey: EnvironmentKey {
    static let defaultValue = EditorConfiguration.default
}

extension EnvironmentValues {
    var editorConfiguration: EditorConfiguration {
        get { self[EditorConfigurationKey.self] }
        set { self[EditorConfigurationKey.self] = newValue }
    }
}
