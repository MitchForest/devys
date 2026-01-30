// PanelContent.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Types of content that can be displayed in a panel.
public enum PanelContent: Identifiable, Equatable, Sendable {
    /// A read-only file viewer.
    case fileViewer(url: URL)
    
    /// An empty panel with placeholder content.
    case empty
    
    /// Unique identifier for this content.
    public var id: String {
        switch self {
        case .fileViewer(let url):
            return "file:\(url.path)"
        case .empty:
            return "empty"
        }
    }
    
    /// Display title for this content.
    public var title: String {
        switch self {
        case .fileViewer(let url):
            return url.lastPathComponent
        case .empty:
            return "Untitled"
        }
    }
    
    /// Icon (SF Symbol) for this content.
    public var icon: String {
        switch self {
        case .fileViewer(let url):
            return CEWorkspaceFileNode.fileTypeIcon(for: url.pathExtension)
        case .empty:
            return "doc"
        }
    }
    
    /// Icon color for this content.
    public var iconColor: IconColor {
        switch self {
        case .fileViewer(let url):
            return CEWorkspaceFileNode.fileTypeColor(for: url.pathExtension)
        case .empty:
            return .tertiary
        }
    }
}
