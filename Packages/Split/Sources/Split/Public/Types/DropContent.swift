// DropContent.swift
// DevysSplit - Types for external drag and drop support

import Foundation
import UniformTypeIdentifiers

/// Content that can be dropped onto a pane from external sources
public enum DropContent: Sendable {
    /// File URLs dropped from Finder or other apps
    case files([URL])
    
    /// Custom typed data (e.g., chat items, git diffs)
    case custom(type: UTType, data: Data)
    
    /// Internal tab being moved (handled automatically by DevysSplit)
    case tab(tabId: TabID, fromPane: PaneID)
}

/// Zone where content was dropped within a pane
public enum DropZone: Equatable, Sendable {
    /// Center of pane - add as new tab
    case center
    
    /// Edge of pane - create split in that direction
    case edge(SplitOrientation)
    
    /// Specific position in tab bar
    case tabBar(index: Int)
}
