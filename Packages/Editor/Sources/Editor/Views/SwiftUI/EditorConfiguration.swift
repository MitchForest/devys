// EditorConfiguration.swift
// DevysEditor - Metal-accelerated code editor
//
// Configuration options for the editor.

import Foundation
import SwiftUI
import UI

// MARK: - Color Scheme

/// Editor color scheme
enum EditorColorScheme: Sendable {
    case light
    case dark
    case system
    
    var codeViewColorScheme: CodeViewColorScheme {
        switch self {
        case .light:
            .light
        case .dark, .system:
            .dark
        }
    }
}

// MARK: - Editor Configuration

/// Configuration for the editor appearance and behavior.
struct EditorConfiguration: Sendable {
    var codeViewDesign: CodeViewDesign

    /// Font name
    var fontName: String { codeViewDesign.fontName }
    
    /// Font size in points
    var fontSize: CGFloat { codeViewDesign.fontSize }

    var lineHeight: CGFloat { codeViewDesign.lineHeight }
    
    /// Color scheme (light/dark)
    var colorScheme: EditorColorScheme {
        didSet {
            codeViewDesign = CodeViewDesign(
                colorScheme: colorScheme.codeViewColorScheme,
                fontName: codeViewDesign.fontName,
                fontSize: codeViewDesign.fontSize,
                lineHeight: codeViewDesign.lineHeight,
                tabWidth: codeViewDesign.tabWidth,
                insertSpacesForTab: codeViewDesign.insertSpacesForTab,
                surfaceDesign: codeViewDesign.surfaceDesign
            )
        }
    }
    
    /// Tab width in spaces
    var tabWidth: Int { codeViewDesign.tabWidth }
    
    /// Insert spaces for tabs
    var insertSpacesForTab: Bool { codeViewDesign.insertSpacesForTab }
    
    /// Theme name (derived from colorScheme)
    var themeName: String {
        codeViewDesign.syntaxThemeName
    }
    
    init(
        codeViewDesign: CodeViewDesign = .dark,
        colorScheme: EditorColorScheme = .dark,
        tabWidth: Int? = nil,
        insertSpacesForTab: Bool? = nil
    ) {
        self.colorScheme = colorScheme
        self.codeViewDesign = CodeViewDesign(
            colorScheme: colorScheme.codeViewColorScheme,
            fontName: codeViewDesign.fontName,
            fontSize: codeViewDesign.fontSize,
            lineHeight: codeViewDesign.lineHeight,
            tabWidth: tabWidth ?? codeViewDesign.tabWidth,
            insertSpacesForTab: insertSpacesForTab ?? codeViewDesign.insertSpacesForTab,
            surfaceDesign: codeViewDesign.surfaceDesign
        )
    }
    
    /// Default configuration from the shared code-view design.
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
