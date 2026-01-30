// CEWorkspaceFileNode.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

/// A class-based file/folder node for the file tree.
///
/// Uses reference semantics (class) for:
/// - Parent pointer traversal without copying
/// - Efficient tree mutations
/// - Observable state for SwiftUI integration
///
/// Inspired by CodeEdit's CEWorkspaceFile architecture.
@MainActor
@Observable
public final class CEWorkspaceFileNode: Identifiable, Hashable {
    // MARK: - Properties
    
    /// Unique identifier for this node.
    public let id: UUID
    
    /// URL to the file or folder.
    public let url: URL
    
    /// Whether this node represents a directory.
    public let isDirectory: Bool
    
    /// Weak reference to parent node (nil for root).
    public weak var parent: CEWorkspaceFileNode?
    
    /// Children of this node (nil = not loaded, empty = loaded but no children).
    public var children: [CEWorkspaceFileNode]?
    
    /// Whether this folder is expanded in the UI.
    public var isExpanded: Bool = false
    
    // MARK: - Computed Properties
    
    /// The file or folder name.
    public var name: String {
        url.lastPathComponent
    }
    
    /// Depth in the tree (0 for root children).
    public var depth: Int {
        var depth = 0
        var current = parent
        while current != nil {
            depth += 1
            current = current?.parent
        }
        return depth
    }
    
    /// SF Symbol name for this file type.
    public var icon: String {
        if isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        return Self.fileTypeIcon(for: url.pathExtension)
    }
    
    /// Color identifier for the icon.
    public var iconColor: IconColor {
        if isDirectory { return .secondary }
        return Self.fileTypeColor(for: url.pathExtension)
    }
    
    // MARK: - Initialization
    
    /// Creates a new file node.
    /// - Parameters:
    ///   - url: URL to the file or folder.
    ///   - isDirectory: Whether this is a directory.
    ///   - parent: Optional parent node.
    public init(url: URL, isDirectory: Bool, parent: CEWorkspaceFileNode? = nil) {
        self.id = UUID()
        self.url = url
        self.isDirectory = isDirectory
        self.parent = parent
    }
    
    // MARK: - Hashable
    
    nonisolated public static func == (lhs: CEWorkspaceFileNode, rhs: CEWorkspaceFileNode) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - File Type Icons
    
    /// Returns the SF Symbol name for a file extension.
    /// - Parameter ext: The file extension (without dot).
    /// - Returns: SF Symbol name.
    nonisolated public static func fileTypeIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "md", "markdown": return "doc.text"
        case "json": return "curlybraces"
        case "js", "ts", "jsx", "tsx": return "j.square"
        case "py": return "p.square"
        case "rs": return "r.square"
        case "go": return "g.square"
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass": return "paintbrush"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "mp3", "wav", "aac", "flac": return "waveform"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "yml", "yaml": return "list.bullet.rectangle"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh": return "terminal"
        case "dockerfile": return "shippingbox"
        case "gitignore", "gitattributes": return "arrow.triangle.branch"
        case "c", "h": return "c.square"
        case "cpp", "cc", "cxx", "hpp": return "c.square"
        case "rb": return "r.square"
        case "php": return "p.square"
        case "java": return "j.square"
        case "kt", "kts": return "k.square"
        case "lock": return "lock"
        case "env": return "key"
        default: return "doc"
        }
    }
    
    /// Returns the color for a file extension.
    /// - Parameter ext: The file extension (without dot).
    /// - Returns: Icon color identifier.
    nonisolated public static func fileTypeColor(for ext: String) -> IconColor {
        switch ext.lowercased() {
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "json": return .green
        case "md", "markdown": return .blue
        case "py": return .blue
        case "rs": return .orange
        case "go": return .cyan
        case "rb": return .red
        case "html", "htm": return .orange
        case "css", "scss", "sass": return .blue
        case "yml", "yaml", "toml": return .purple
        default: return .tertiary
        }
    }
}

/// Color identifiers for file icons.
public enum IconColor: String, Sendable {
    case orange
    case yellow
    case green
    case blue
    case cyan
    case red
    case purple
    case secondary
    case tertiary
}
