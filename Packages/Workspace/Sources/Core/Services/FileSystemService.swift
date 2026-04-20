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
    private struct FileSystemEntry: Sendable {
        let url: URL
        let isDirectory: Bool
    }

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
        rootNode.children = await buildChildNodes(
            in: rootURL,
            parent: rootNode,
            explorerSettings: explorerSettings
        )
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

        return await buildChildNodes(
            in: parent.url,
            parent: parent,
            explorerSettings: explorerSettings
        )
    }

}

private extension FileSystemService {
    @MainActor
    static func buildChildNodes(
        in directoryURL: URL,
        parent: CEWorkspaceFileNode,
        explorerSettings: ExplorerSettings
    ) async -> [CEWorkspaceFileNode] {
        let entries = await scanDirectory(
            at: directoryURL,
            explorerSettings: explorerSettings
        )

        return entries.map { entry in
            CEWorkspaceFileNode(
                url: entry.url,
                isDirectory: entry.isDirectory,
                parent: parent
            )
        }
    }

    private static func scanDirectory(
        at directoryURL: URL,
        explorerSettings: ExplorerSettings
    ) async -> [FileSystemEntry] {
        let task = Task.detached(priority: .utility) {
            do {
                // Don't use .skipsHiddenFiles - we handle filtering ourselves
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                    options: []
                )

                let entries = contents.compactMap { url -> FileSystemEntry? in
                    let filename = url.lastPathComponent

                    if explorerSettings.shouldExclude(filename) {
                        return nil
                    }

                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    return FileSystemEntry(
                        url: url.standardizedFileURL,
                        isDirectory: isDirectory
                    )
                }

                return entries.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory
                    }
                    return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
                        == .orderedAscending
                }
            } catch {
                let path = directoryURL.path
                let errorDescription = String(describing: error)
                logger.error(
                    "Error loading children for \(path, privacy: .public): \(errorDescription, privacy: .public)"
                )
                return []
            }
        }

        return await task.value
    }
}
