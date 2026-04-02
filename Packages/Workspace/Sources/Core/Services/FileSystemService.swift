// FileSystemService.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.devys.core", category: "FileSystemService")

/// Service for file system operations including tree building and file I/O.
///
/// All methods are async to support background operations and
/// non-blocking UI updates.
enum FileSystemService {
    // MARK: - Tree Building
    
    /// Builds a file tree from a root URL.
    /// - Parameter rootURL: The root folder URL.
    /// - Returns: The root file node with immediate children loaded.
    @MainActor
    static func buildTree(
        from rootURL: URL,
        explorerSettings: ExplorerSettings
    ) async -> CEWorkspaceFileNode {
        let rootNode = CEWorkspaceFileNode(url: rootURL, isDirectory: true)
        rootNode.children = await loadChildren(for: rootNode, explorerSettings: explorerSettings)
        return rootNode
    }
    
    /// Loads children for a directory node.
    /// - Parameter parent: The parent directory node.
    /// - Returns: Array of child nodes, sorted directories-first then alphabetically.
    @MainActor
    static func loadChildren(
        for parent: CEWorkspaceFileNode,
        explorerSettings: ExplorerSettings
    ) async -> [CEWorkspaceFileNode] {
        guard parent.isDirectory else { return [] }
        
        return await Task.detached {
            await loadChildrenSync(for: parent, explorerSettings: explorerSettings)
        }.value
    }
    
    @MainActor
    private static func loadChildrenSync(
        for parent: CEWorkspaceFileNode,
        explorerSettings: ExplorerSettings
    ) -> [CEWorkspaceFileNode] {
        do {
            // Don't use .skipsHiddenFiles - we handle filtering ourselves
            let contents = try FileManager.default.contentsOfDirectory(
                at: parent.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: []
            )
            
            let nodes = contents.compactMap { url -> CEWorkspaceFileNode? in
                let filename = url.lastPathComponent
                
                // Use settings to determine if file should be excluded
                if explorerSettings.shouldExclude(filename) {
                    return nil
                }
                
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
            let path = parent.url.path
            logger.error(
                "Error loading children for \(path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }
    
}
