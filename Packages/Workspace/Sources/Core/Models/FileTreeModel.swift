// FileTreeModel.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

/// Manages the file tree state for efficient virtualized rendering.
///
/// This model:
/// - Maintains the tree structure with lazy loading
/// - Provides a flattened list for LazyVStack rendering
/// - Handles expansion state and file watching
@MainActor
@Observable
public final class FileTreeModel {
    // MARK: - Properties
    
    /// Flattened nodes for virtualized rendering.
    public private(set) var flattenedNodes: [FlatFileNode] = []
    
    /// Currently selected node.
    public var selectedNode: CEWorkspaceFileNode?
    
    /// Whether the tree is loading.
    public private(set) var isLoading = false
    
    /// The root URL of the file tree.
    let rootURL: URL

    /// Settings model for explorer configuration.
    private let settings: AppSettings

    /// Service for file tree loading.
    private let fileTreeService: FileTreeService

    /// Factory for creating file watch services per root.
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    
    // MARK: - Private Properties
    
    private var rootNode: CEWorkspaceFileNode?
    private var fileWatchService: FileWatchService?
    
    // MARK: - Initialization
    
    /// Creates a new file tree model.
    /// - Parameter rootURL: The root folder URL.
    public convenience init(rootURL: URL, settings: AppSettings) {
        self.init(
            rootURL: rootURL,
            settings: settings,
            fileTreeService: DefaultFileTreeService()
        ) { DefaultFileWatchService(rootURL: $0) }
    }

    public init(
        rootURL: URL,
        settings: AppSettings,
        fileTreeService: FileTreeService,
        fileWatchServiceFactory: @escaping (URL) -> FileWatchService
    ) {
        self.rootURL = rootURL
        self.settings = settings
        self.fileTreeService = fileTreeService
        self.fileWatchServiceFactory = fileWatchServiceFactory
    }
    
    // Note: fileWatchService cleanup is handled automatically when the model is deallocated.
    
    // MARK: - Public Methods
    
    /// Loads the file tree from the root URL.
    public func loadTree() async {
        isLoading = true
        defer { isLoading = false }
        
        rootNode = await fileTreeService.buildTree(
            rootURL: rootURL,
            explorerSettings: settings.explorer
        )
        rebuildFlattenedList()
        startWatching()
    }
    
    /// Toggles expansion state of a directory node.
    /// - Parameter node: The node to toggle.
    public func toggleExpansion(_ node: CEWorkspaceFileNode) {
        guard node.isDirectory else { return }
        
        node.isExpanded.toggle()
        
        // Load children if needed
        if node.isExpanded && node.children == nil {
            Task {
                await loadChildren(for: node)
                rebuildFlattenedList()
                
                // Watch this directory for changes
                fileWatchService?.watchDirectory(node.url)
            }
        } else {
            rebuildFlattenedList()
            
            // Stop watching if collapsed
            if !node.isExpanded {
                fileWatchService?.unwatchDirectory(node.url)
            }
        }
    }
    
    /// Refreshes the file tree.
    public func refresh() async {
        await loadTree()
    }
    
    /// Expands all ancestors of a given URL to reveal it in the tree.
    /// - Parameter url: The URL to reveal.
    public func revealURL(_ url: URL) async {
        guard let rootNode = rootNode else { return }
        
        // Find path from root to URL
        let relativePath = url.path.replacingOccurrences(of: rootURL.path, with: "")
        let components = relativePath.split(separator: "/").map(String.init)
        
        var currentNode = rootNode
        
        for component in components {
            guard currentNode.isDirectory else { break }
            
            if currentNode.children == nil {
                await loadChildren(for: currentNode)
            }
            
            if !currentNode.isExpanded {
                currentNode.isExpanded = true
                fileWatchService?.watchDirectory(currentNode.url)
            }
            
            if let child = currentNode.children?.first(where: { $0.name == component }) {
                currentNode = child
            } else {
                break
            }
        }
        
        selectedNode = currentNode
        rebuildFlattenedList()
    }
    
    // MARK: - Private Methods
    
    private func loadChildren(for node: CEWorkspaceFileNode) async {
        node.children = await fileTreeService.loadChildren(
            for: node,
            explorerSettings: settings.explorer
        )
    }
    
    private func rebuildFlattenedList() {
        var result: [FlatFileNode] = []
        
        func flatten(_ nodes: [CEWorkspaceFileNode]) {
            for (index, node) in nodes.enumerated() {
                let isLast = index == nodes.count - 1
                result.append(FlatFileNode(node: node, isLastChild: isLast))
                
                if node.isDirectory && node.isExpanded, let children = node.children {
                    flatten(children)
                }
            }
        }
        
        if let root = rootNode, let children = root.children {
            flatten(children)
        }
        
        flattenedNodes = result
    }
    
    private func startWatching() {
        fileWatchService = fileWatchServiceFactory(rootURL)
        fileWatchService?.onFileChange = { [weak self] changeType, url in
            Task { @MainActor in
                await self?.handleFileChange(changeType, at: url)
            }
        }
        fileWatchService?.startWatching()
    }
    
    private func handleFileChange(_ changeType: FileChangeType, at url: URL) async {
        let shouldReloadAll = (changeType == .deleted || changeType == .renamed)
        // Find the parent node and reload its children
        if !shouldReloadAll, let parentNode = findNode(for: url.deletingLastPathComponent()) {
            await loadChildren(for: parentNode)
        } else {
            // Fallback: reload entire tree
            await loadTree()
        }
        rebuildFlattenedList()
    }
    
    private func findNode(for url: URL) -> CEWorkspaceFileNode? {
        guard let rootNode = rootNode else { return nil }
        
        func search(_ node: CEWorkspaceFileNode) -> CEWorkspaceFileNode? {
            if node.url == url { return node }
            for child in node.children ?? [] {
                if let found = search(child) { return found }
            }
            return nil
        }
        
        return search(rootNode)
    }
}
