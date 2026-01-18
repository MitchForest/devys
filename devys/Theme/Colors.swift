//
//  Colors.swift
//  devys
//
//  Semantic color definitions for the design system.
//

import SwiftUI

extension Color {
    // MARK: - Backgrounds
    
    /// Main editor background
    static let editorBackground = Color("Colors/EditorBackground")
    
    /// Sidebar and navigator background
    static let sidebarBackground = Color("Colors/SidebarBackground")
    
    // MARK: - Text
    
    /// Primary text (code, headings)
    static let textPrimary = Color("Colors/TextPrimary")
    
    // MARK: - Status
    
    /// Success states (additions, connected)
    static let statusSuccess = Color("Colors/StatusSuccess")
    
    /// Error states (deletions, errors)
    static let statusError = Color("Colors/StatusError")
}

// MARK: - Diff Colors

extension Color {
    /// Background for added lines in diffs
    static var diffAdditionBackground: Color {
        statusSuccess.opacity(0.15)
    }
    
    /// Background for removed lines in diffs
    static var diffDeletionBackground: Color {
        statusError.opacity(0.15)
    }
    
    /// Text color for additions
    static var diffAdditionText: Color {
        statusSuccess
    }
    
    /// Text color for deletions
    static var diffDeletionText: Color {
        statusError
    }
}
