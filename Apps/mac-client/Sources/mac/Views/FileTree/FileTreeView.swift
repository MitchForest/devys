// FileTreeView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import AppKit
import Workspace
import UI

/// Virtualized file tree using LazyVStack for performance.
///
/// Renders a flattened list of file nodes with:
/// - Lazy loading (only visible rows rendered)
/// - Single-click folders: select and toggle expansion
/// - Single-click files: preview file (VS Code-style reusable tab)
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
    let onRenameItem: ((URL) -> Void)?     // Context menu: rename file/folder
    let onDeleteItems: (([URL]) -> Void)?  // Context menu: delete selected items
    
    // Track settings to trigger refresh on change
    private var explorerSettings: ExplorerSettings {
        appSettings.explorer
    }
    
    init(
        model: FileTreeModel,
        gitStatusIndex: WorkspaceFileTreeGitStatusIndex? = nil,
        onPreviewFile: ((URL) -> Void)? = nil,
        onOpenFile: @escaping (URL) -> Void,
        onAddToChat: ((URL) -> Void)? = nil,
        onRenameItem: ((URL) -> Void)? = nil,
        onDeleteItems: (([URL]) -> Void)? = nil
    ) {
        self.model = model
        self.gitStatusIndex = gitStatusIndex
        self.onPreviewFile = onPreviewFile
        self.onOpenFile = onOpenFile
        self.onAddToChat = onAddToChat
        self.onRenameItem = onRenameItem
        self.onDeleteItems = onDeleteItems
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
                .font(Typography.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: DevysSpacing.space2) {
            Image(systemName: "folder")
                .font(Typography.display.weight(.light))
                .foregroundStyle(.tertiary)
            Text("Empty folder")
                .font(Typography.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - File List
    
    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(model.flattenedNodes) { flatNode in
                    let resolvedRenameTarget = renameTarget(for: flatNode.node.url)
                    let resolvedDeleteTargets = deleteTargets(for: flatNode.node.url)
                    FileTreeRow(
                        flatNode: flatNode,
                        gitStatusSummary: gitStatusIndex?.summary(for: flatNode.node),
                        isSelected: model.isSelected(flatNode.node.url),
                        canRename: resolvedRenameTarget != nil,
                        onPrimaryClick: { modifiers in
                            handlePrimaryClick(for: flatNode.node, modifiers: modifiers)
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
                        onAddToChat: onAddToChat,
                        onRename: {
                            guard let resolvedRenameTarget else { return }
                            onRenameItem?(resolvedRenameTarget)
                        },
                        onDelete: {
                            onDeleteItems?(resolvedDeleteTargets)
                        }
                    )
                }
            }
            .padding(.vertical, DevysSpacing.space1)
        }
    }

    private var visibleURLs: [URL] {
        model.flattenedNodes.map { $0.node.url.standardizedFileURL }
    }

    private func handlePrimaryClick(
        for node: CEWorkspaceFileNode,
        modifiers: NSEvent.ModifierFlags
    ) {
        let normalizedURL = node.url.standardizedFileURL

        switch fileTreePrimaryClickBehavior(
            isDirectory: node.isDirectory,
            modifiers: modifiers
        ) {
        case .selectRange:
            model.selectRange(to: normalizedURL, visibleURLs: visibleURLs)
        case .toggleSelection:
            model.toggleSelection(of: normalizedURL)
        case .selectAndToggleDirectory:
            model.replaceSelection(with: normalizedURL)
            model.toggleExpansion(node)
        case .selectAndPreviewFile:
            model.replaceSelection(with: normalizedURL)
            onPreviewFile?(normalizedURL)
        }
    }

    private func renameTarget(for clickedURL: URL) -> URL? {
        let normalizedClickedURL = clickedURL.standardizedFileURL
        if model.isSelected(normalizedClickedURL) {
            return model.selectedURLs.count == 1 ? normalizedClickedURL : nil
        }
        return normalizedClickedURL
    }

    private func deleteTargets(for clickedURL: URL) -> [URL] {
        let normalizedClickedURL = clickedURL.standardizedFileURL
        let rawTargets: Set<URL>
        if model.isSelected(normalizedClickedURL) {
            rawTargets = model.selectedURLs.isEmpty ? [normalizedClickedURL] : model.selectedURLs
        } else {
            rawTargets = [normalizedClickedURL]
        }

        let sortedTargets = Array(rawTargets).sorted { $0.path < $1.path }
        return sortedTargets.filter { candidate in
            !sortedTargets.contains { other in
                other != candidate && isAncestor(other, of: candidate)
            }
        }
    }

    private func isAncestor(_ candidateAncestor: URL, of url: URL) -> Bool {
        let ancestorPath = candidateAncestor.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath.hasPrefix(ancestorPath + "/")
    }
}
