// PanelLayout.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Serializable representation of the Bonsplit panel layout.
///
/// This struct captures the hierarchical tree structure of splits
/// and panes for persistence across app launches.
public struct PanelLayout: Codable, Equatable, Sendable {
    /// The root node of the panel tree.
    public var tree: PanelNode
    
    /// Creates a new panel layout with the given root node.
    /// - Parameter tree: The root panel node.
    public init(tree: PanelNode) {
        self.tree = tree
    }
    
    /// Creates a default layout with a single empty pane.
    public static var `default`: PanelLayout {
        PanelLayout(tree: .pane(PaneData.empty))
    }
}

/// A node in the panel layout tree.
///
/// Can be either a leaf pane or a split container.
public enum PanelNode: Codable, Equatable, Sendable {
    /// A leaf pane containing tabs.
    case pane(PaneData)
    
    /// A split container with orientation, children, and size ratios.
    case split(
        orientation: SplitOrientation,
        children: [PanelNode],
        ratios: [CGFloat]
    )
}

/// Orientation of a split container.
public enum SplitOrientation: String, Codable, Sendable {
    /// Horizontal split (panes arranged left-to-right).
    case horizontal
    
    /// Vertical split (panes arranged top-to-bottom).
    case vertical
}

/// Data for a single pane, containing multiple tabs.
public struct PaneData: Codable, Equatable, Sendable {
    /// Unique identifier for this pane.
    public let id: UUID
    
    /// Tabs within this pane.
    public var tabs: [TabData]
    
    /// Index of the currently selected tab.
    public var selectedTabIndex: Int
    
    /// Creates an empty pane.
    public static var empty: PaneData {
        PaneData(id: UUID(), tabs: [], selectedTabIndex: 0)
    }
    
    /// Creates a pane with the given tabs.
    /// - Parameters:
    ///   - id: Unique identifier.
    ///   - tabs: Array of tabs.
    ///   - selectedTabIndex: Index of selected tab.
    public init(id: UUID, tabs: [TabData], selectedTabIndex: Int) {
        self.id = id
        self.tabs = tabs
        self.selectedTabIndex = selectedTabIndex
    }
}

/// Data for a single tab.
public struct TabData: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this tab.
    public let id: UUID
    
    /// File path if this tab represents a file (nil for empty tabs).
    public var filePath: String?
    
    /// Display title for the tab.
    public var title: String
    
    /// Icon name (SF Symbol) for the tab.
    public var icon: String
    
    /// Whether the tab has unsaved changes.
    public var isDirty: Bool
    
    /// Creates a new tab.
    /// - Parameters:
    ///   - id: Unique identifier.
    ///   - filePath: Optional file path.
    ///   - title: Display title.
    ///   - icon: SF Symbol name.
    ///   - isDirty: Whether tab has unsaved changes.
    public init(
        id: UUID = UUID(),
        filePath: String? = nil,
        title: String,
        icon: String = "doc",
        isDirty: Bool = false
    ) {
        self.id = id
        self.filePath = filePath
        self.title = title
        self.icon = icon
        self.isDirty = isDirty
    }
}
