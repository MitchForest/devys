// FileSystemService.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Service for file system operations including tree building and file I/O.
///
/// All methods are async to support background operations and
/// non-blocking UI updates.
public enum FileSystemService {
    // MARK: - Tree Building
    
    /// Builds a file tree from a root URL.
    /// - Parameter rootURL: The root folder URL.
    /// - Returns: The root file node with immediate children loaded.
    @MainActor
    public static func buildTree(from rootURL: URL) async -> CEWorkspaceFileNode {
        let rootNode = CEWorkspaceFileNode(url: rootURL, isDirectory: true)
        rootNode.children = await loadChildren(for: rootNode)
        return rootNode
    }
    
    /// Loads children for a directory node.
    /// - Parameter parent: The parent directory node.
    /// - Returns: Array of child nodes, sorted directories-first then alphabetically.
    @MainActor
    public static func loadChildren(for parent: CEWorkspaceFileNode) async -> [CEWorkspaceFileNode] {
        guard parent.isDirectory else { return [] }
        
        return await Task.detached {
            await loadChildrenSync(for: parent)
        }.value
    }
    
    @MainActor
    private static func loadChildrenSync(for parent: CEWorkspaceFileNode) -> [CEWorkspaceFileNode] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: parent.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
            
            let nodes = contents.compactMap { url -> CEWorkspaceFileNode? in
                // Skip hidden files
                guard !url.lastPathComponent.hasPrefix(".") else { return nil }
                
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return CEWorkspaceFileNode(url: url, isDirectory: isDirectory, parent: parent)
            }
            
            // Sort: directories first, then alphabetically
            return nodes.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            print("Error loading children for \(parent.url): \(error)")
            return []
        }
    }
    
    // MARK: - File Operations
    
    /// Reads the contents of a text file.
    /// - Parameter url: The file URL.
    /// - Returns: The file contents as a string.
    /// - Throws: If the file cannot be read.
    public static func readFile(at url: URL) async throws -> String {
        try await Task.detached {
            try String(contentsOf: url, encoding: .utf8)
        }.value
    }
    
    /// Gets file information.
    /// - Parameter url: The file URL.
    /// - Returns: File info including size and dates.
    /// - Throws: If file attributes cannot be read.
    public static func fileInfo(at url: URL) throws -> FileInfo {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileInfo(
            size: attributes[.size] as? Int64 ?? 0,
            modifiedDate: attributes[.modificationDate] as? Date ?? Date(),
            createdDate: attributes[.creationDate] as? Date ?? Date()
        )
    }
    
    /// Checks if a file is likely binary (non-text).
    /// - Parameter url: The file URL.
    /// - Returns: True if the file appears to be binary.
    public static func isBinaryFile(at url: URL) -> Bool {
        let binaryExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "ico", "bmp", "tiff",
            "mp3", "wav", "aac", "flac", "ogg", "m4a",
            "mp4", "mov", "avi", "mkv", "webm",
            "pdf", "zip", "tar", "gz", "rar", "7z",
            "exe", "dll", "dylib", "so", "a", "o",
            "sqlite", "db", "wasm"
        ]
        
        return binaryExtensions.contains(url.pathExtension.lowercased())
    }
}

/// Information about a file.
public struct FileInfo: Sendable {
    /// File size in bytes.
    public let size: Int64
    
    /// Last modification date.
    public let modifiedDate: Date
    
    /// Creation date.
    public let createdDate: Date
    
    /// Formatted file size string.
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
