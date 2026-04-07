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
public final class CEWorkspaceFileNode: Identifiable {
    // MARK: - Properties
    
    /// Unique identifier for this node.
    public let id: UUID
    
    /// URL to the file or folder.
    public var url: URL
    
    /// Whether this node represents a directory.
    public let isDirectory: Bool
    
    /// Weak reference to parent node (nil for root).
    weak var parent: CEWorkspaceFileNode?
    
    /// Children of this node (nil = not loaded, empty = loaded but no children).
    var children: [CEWorkspaceFileNode]?
    
    /// Whether this folder is expanded in the UI.
    var isExpanded: Bool = false
    
    // MARK: - Computed Properties
    
    /// The file or folder name.
    public var name: String {
        url.lastPathComponent
    }
    
    /// Depth in the tree (0 for root children).
    var depth: Int {
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
    
    // MARK: - File Type Icons
    
    /// Returns the SF Symbol name for a file extension.
    /// - Parameter ext: The file extension (without dot).
    /// - Returns: SF Symbol name.
    nonisolated public static func fileTypeIcon(for ext: String) -> String {
        let key = ext.lowercased()
        return fileTypeIconByExtension[key] ?? "doc"
    }
    
    /// Returns the color for a file extension.
    /// - Parameter ext: The file extension (without dot).
    /// - Returns: Icon color identifier.
    nonisolated static func fileTypeColor(for ext: String) -> IconColor {
        let key = ext.lowercased()
        return fileTypeColorByExtension[key] ?? .tertiary
    }
}

private let fileTypeIconByExtension: [String: String] = [
    "swift": "swift",
    "md": "doc.text",
    "markdown": "doc.text",
    "json": "curlybraces",
    "js": "j.square",
    "ts": "j.square",
    "jsx": "j.square",
    "tsx": "j.square",
    "py": "p.square",
    "rs": "r.square",
    "go": "g.square",
    "html": "chevron.left.forwardslash.chevron.right",
    "htm": "chevron.left.forwardslash.chevron.right",
    "css": "paintbrush",
    "scss": "paintbrush",
    "sass": "paintbrush",
    "png": "photo",
    "jpg": "photo",
    "jpeg": "photo",
    "gif": "photo",
    "svg": "photo",
    "webp": "photo",
    "mp3": "waveform",
    "wav": "waveform",
    "aac": "waveform",
    "flac": "waveform",
    "mp4": "film",
    "mov": "film",
    "avi": "film",
    "mkv": "film",
    "pdf": "doc.richtext",
    "zip": "doc.zipper",
    "tar": "doc.zipper",
    "gz": "doc.zipper",
    "rar": "doc.zipper",
    "yml": "list.bullet.rectangle",
    "yaml": "list.bullet.rectangle",
    "xml": "chevron.left.forwardslash.chevron.right",
    "sh": "terminal",
    "bash": "terminal",
    "zsh": "terminal",
    "dockerfile": "shippingbox",
    "gitignore": "arrow.triangle.branch",
    "gitattributes": "arrow.triangle.branch",
    "c": "c.square",
    "h": "c.square",
    "cpp": "c.square",
    "cc": "c.square",
    "cxx": "c.square",
    "hpp": "c.square",
    "rb": "r.square",
    "php": "p.square",
    "java": "j.square",
    "kt": "k.square",
    "kts": "k.square",
    "lock": "lock",
    "env": "key"
]

private let fileTypeColorByExtension: [String: IconColor] = [
    "swift": .orange,
    "js": .yellow,
    "ts": .yellow,
    "jsx": .yellow,
    "tsx": .yellow,
    "json": .green,
    "md": .blue,
    "markdown": .blue,
    "py": .blue,
    "rs": .orange,
    "go": .cyan,
    "rb": .red,
    "html": .orange,
    "htm": .orange,
    "css": .blue,
    "scss": .blue,
    "sass": .blue,
    "yml": .purple,
    "yaml": .purple,
    "toml": .purple
]

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
