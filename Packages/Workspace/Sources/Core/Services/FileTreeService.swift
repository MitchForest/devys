// FileTreeService.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Abstraction for file tree loading operations.
@MainActor
public protocol FileTreeService {
    func buildTree(rootURL: URL, explorerSettings: ExplorerSettings) async -> CEWorkspaceFileNode
    func loadChildren(for node: CEWorkspaceFileNode, explorerSettings: ExplorerSettings) async -> [CEWorkspaceFileNode]
}

@MainActor
public struct DefaultFileTreeService: FileTreeService {
    public init() {}

    public func buildTree(rootURL: URL, explorerSettings: ExplorerSettings) async -> CEWorkspaceFileNode {
        await FileSystemService.buildTree(from: rootURL, explorerSettings: explorerSettings)
    }

    public func loadChildren(
        for node: CEWorkspaceFileNode,
        explorerSettings: ExplorerSettings
    ) async -> [CEWorkspaceFileNode] {
        await FileSystemService.loadChildren(for: node, explorerSettings: explorerSettings)
    }
}
