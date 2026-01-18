//
//  Workspace.swift
//  devys
//
//  A workspace is a project folder. This is the ONLY thing we persist.
//  Everything else comes from the CLI.
//

import Foundation
import SwiftData

/// A workspace represents a project folder.
/// This is persisted to SwiftData so we remember which folders the user has added.
@Model
final class Workspace {
    /// Unique identifier
    var id: UUID
    
    /// Display name (defaults to folder name)
    var name: String
    
    /// Absolute path to the project folder
    var path: String
    
    /// When the workspace was added
    var createdAt: Date
    
    /// When the workspace was last accessed
    var lastAccessedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
    
    /// Create a workspace from a folder URL
    convenience init(url: URL) {
        self.init(
            name: url.lastPathComponent,
            path: url.path
        )
    }
    
    /// URL representation of the path
    var url: URL {
        URL(fileURLWithPath: path)
    }
    
    /// Update last accessed timestamp
    func touch() {
        lastAccessedAt = Date()
    }
}
