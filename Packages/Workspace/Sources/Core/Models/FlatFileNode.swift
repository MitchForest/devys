// FlatFileNode.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// A flattened representation of a file node for virtualized rendering.
///
/// This struct is used by the FileTreeView to render a flat list
/// with LazyVStack, enabling virtualization for performance.
public struct FlatFileNode: Identifiable, Sendable {
    /// The unique identifier (same as the underlying node).
    public let id: UUID
    
    /// Reference to the underlying file node.
    public let node: CEWorkspaceFileNode
    
    /// Depth in the tree for indentation.
    public let depth: Int
    
    /// Whether this node is currently expanded.
    public let isExpanded: Bool
    
    /// Whether this node has children (for showing chevron).
    public let hasChildren: Bool
    
    /// Whether this is the last child of its parent (for tree lines).
    public let isLastChild: Bool
    
    /// Creates a flattened file node.
    /// - Parameters:
    ///   - node: The underlying file node.
    ///   - isLastChild: Whether this is the last child of its parent.
    @MainActor
    public init(node: CEWorkspaceFileNode, isLastChild: Bool = false) {
        self.id = node.id
        self.node = node
        self.depth = node.depth
        self.isExpanded = node.isExpanded
        self.hasChildren = node.isDirectory && (node.children?.isEmpty == false || node.children == nil)
        self.isLastChild = isLastChild
    }
}
