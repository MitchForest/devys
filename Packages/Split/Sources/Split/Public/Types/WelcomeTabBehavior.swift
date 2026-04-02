// WelcomeTabBehavior.swift
// DevysSplit - Configuration for automatic welcome tabs

import Foundation

/// Controls behavior of welcome tabs in empty panes
public enum WelcomeTabBehavior: Sendable {
    /// No automatic welcome tabs
    case none
    
    /// Auto-create welcome tab in empty panes; closing it closes the pane
    case autoCreateAndClosePane
    
    /// Auto-create welcome tab but don't close pane when it's closed
    case autoCreateOnly
}
