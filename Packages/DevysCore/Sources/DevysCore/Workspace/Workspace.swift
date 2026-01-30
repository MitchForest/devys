// Workspace.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents a workspace in Devys, corresponding to a project folder.
///
/// A workspace encapsulates:
/// - A root folder path
/// - Panel layout state
/// - Last opened timestamp for recency sorting
public struct Workspace: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this workspace.
    public let id: UUID
    
    /// Display name of the workspace (usually the folder name).
    public var name: String
    
    /// URL to the workspace root folder.
    public var path: URL
    
    /// When this workspace was last opened.
    public var lastOpened: Date
    
    /// Serialized panel layout (optional, restored on workspace open).
    public var panelLayout: PanelLayout?
    
    /// Creates a new workspace.
    /// - Parameters:
    ///   - name: Display name for the workspace.
    ///   - path: URL to the workspace root folder.
    public init(name: String, path: URL) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.lastOpened = Date()
        self.panelLayout = nil
    }
    
    /// Creates a workspace with all properties specified.
    /// - Parameters:
    ///   - id: Unique identifier.
    ///   - name: Display name.
    ///   - path: Root folder URL.
    ///   - lastOpened: Last opened timestamp.
    ///   - panelLayout: Optional panel layout.
    public init(
        id: UUID,
        name: String,
        path: URL,
        lastOpened: Date,
        panelLayout: PanelLayout?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.lastOpened = lastOpened
        self.panelLayout = panelLayout
    }
}
