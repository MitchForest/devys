// WindowState.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

/// Per-window state for managing the open folder.
///
/// Each window has its own WindowState instance.
/// - One folder per window
/// - Multi-window is allowed, same folder in multiple windows allowed
@MainActor
@Observable
public final class WindowState {
    // MARK: - Properties

    /// The folder currently open in this window.
    public private(set) var folder: URL?
    
    // MARK: - Computed Properties
    
    /// Whether any folders are open.
    public var hasFolder: Bool {
        folder != nil
    }
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Folder Operations
    
    /// Opens (or replaces) the folder in this window.
    /// - Parameter url: The folder URL to open.
    public func openFolder(_ url: URL) {
        folder = url
    }
}
