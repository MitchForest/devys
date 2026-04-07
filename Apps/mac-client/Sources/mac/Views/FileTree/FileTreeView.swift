// FileTreeView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI

/// Virtualized file tree using LazyVStack for performance.
///
/// Renders a flattened list of file nodes with:
/// - Lazy loading (only visible rows rendered)
/// - Expand/collapse directories
/// - Single-click: preview file (VS Code-style reusable tab)
/// - Double-click: open file permanently
/// - Context menus
public struct FileTreeView: View {
    // MARK: - Properties
    
    @Environment(AppSettings.self) private var appSettings
    let model: FileTreeModel
    let gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    let onPreviewFile: ((URL) -> Void)?   // Single-click: preview tab
    let onOpenFile: (URL) -> Void          // Double-click: permanent tab
    let onAddToChat: ((URL) -> Void)?      // Context menu: add to chat
    
    // Track settings to trigger refresh on change
    private var explorerSettings: ExplorerSettings {
        appSettings.explorer
    }
    
    init(
        model: FileTreeModel,
        gitStatusIndex: WorkspaceFileTreeGitStatusIndex? = nil,
        onPreviewFile: ((URL) -> Void)? = nil,
        onOpenFile: @escaping (URL) -> Void,
        onAddToChat: ((URL) -> Void)? = nil
    ) {
        self.model = model
        self.gitStatusIndex = gitStatusIndex
        self.onPreviewFile = onPreviewFile
        self.onOpenFile = onOpenFile
        self.onAddToChat = onAddToChat
    }
    
    // MARK: - Body
    
    public var body: some View {
        Group {
            if model.isLoading {
                loadingView
            } else if model.flattenedNodes.isEmpty {
                emptyView
            } else {
                fileList
            }
        }
        .task {
            await model.loadTreeIfNeeded()
        }
        .onChange(of: explorerSettings) { _, _ in
            // Refresh tree when explorer settings change (e.g., show hidden files)
            Task {
                await model.refresh()
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DevysSpacing.space3) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading files...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: DevysSpacing.space2) {
            Image(systemName: "folder")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Empty folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - File List
    
    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(model.flattenedNodes) { flatNode in
                    FileTreeRow(
                        flatNode: flatNode,
                        gitStatusSummary: gitStatusIndex?.summary(for: flatNode.node),
                        isSelected: model.selectedNode?.id == flatNode.id,
                        onSelect: {
                            model.selectedNode = flatNode.node
                            // Single-click: open in preview tab (VS Code-style)
                            if !flatNode.node.isDirectory {
                                onPreviewFile?(flatNode.node.url)
                            }
                        },
                        onToggleExpand: {
                            model.toggleExpansion(flatNode.node)
                        },
                        onOpenFile: {
                            // Double-click: open in permanent tab
                            if !flatNode.node.isDirectory {
                                onOpenFile(flatNode.node.url)
                            }
                        },
                        onAddToChat: onAddToChat
                    )
                }
            }
            .padding(.vertical, DevysSpacing.space1)
        }
    }
}
