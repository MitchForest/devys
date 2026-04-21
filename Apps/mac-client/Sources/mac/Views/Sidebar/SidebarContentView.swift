// SidebarContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI

/// The expandable sidebar content showing workspace files for the active directory.
///
/// Tab opening behavior (VS Code-style):
/// - Single click: Opens in preview tab (reusable) via `onPreviewFile`
/// - Double click: Opens in permanent tab via `onOpenFile`
struct SidebarContentView: View {
    @Environment(\.devysTheme) private var theme

    // MARK: - Properties

    let model: FileTreeModel?
    let activeDirectory: URL?
    let gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    let onPreviewFile: (URL) -> Void   // Single-click: preview tab
    let onOpenFile: (URL) -> Void      // Double-click: permanent tab
    let onAddToChat: ((URL) -> Void)?  // Context menu: add file to chat
    let onRenameItem: ((URL) -> Void)? // Context menu: rename file/folder
    let onDeleteItems: (([URL]) -> Void)? // Context menu: delete selected items
    let showsTrailingBorder: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsTrailingBorder {
                Rectangle()
                    .fill(theme.border)
                    .frame(width: 1)
            }
        }
        .background(theme.card)
    }

    @ViewBuilder
    private var contentArea: some View {
        if let activeDirectory {
            SingleFolderTreeView(
                model: model,
                folder: activeDirectory,
                gitStatusIndex: gitStatusIndex,
                onPreviewFile: onPreviewFile,
                onOpenFile: onOpenFile,
                onAddToChat: onAddToChat,
                onRenameItem: onRenameItem,
                onDeleteItems: onDeleteItems
            )
        } else {
            EmptyState(
                icon: "folder.badge.questionmark",
                title: "Select a Workspace",
                description: "Choose a worktree from the repo rail to load files for the active workspace."
            )
        }
    }
}

// MARK: - Single Folder Tree View

private struct SingleFolderTreeView: View {
    let model: FileTreeModel?
    let folder: URL
    let gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    let onPreviewFile: (URL) -> Void   // Single-click
    let onOpenFile: (URL) -> Void       // Double-click
    let onAddToChat: ((URL) -> Void)?   // Context menu: add to chat
    let onRenameItem: ((URL) -> Void)?
    let onDeleteItems: (([URL]) -> Void)?

    var body: some View {
        Group {
            if let model = model {
                FileTreeView(
                    model: model,
                    gitStatusIndex: gitStatusIndex,
                    onPreviewFile: onPreviewFile,
                    onOpenFile: onOpenFile,
                    onAddToChat: onAddToChat,
                    onRenameItem: onRenameItem,
                    onDeleteItems: onDeleteItems
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Preview

@MainActor
private struct SidebarContentViewPreviewHost: View {
    private let container = AppContainer()
    private let activeDirectory = URL(fileURLWithPath: "/Users/test/Code/devys")

    var body: some View {
        SidebarContentView(
            model: nil,
            activeDirectory: activeDirectory,
            gitStatusIndex: nil,
            onPreviewFile: { _ in },
            onOpenFile: { _ in },
            onAddToChat: { _ in },
            onRenameItem: { _ in },
            onDeleteItems: { _ in },
            showsTrailingBorder: true
        )
        .frame(width: 240, height: 400)
        .environment(container)
        .environment(container.appSettings)
        .environment(container.recentRepositoriesService)
        .environment(container.layoutPersistenceService)
        .environment(\.devysTheme, DevysTheme(isDark: false))
    }
}

#Preview("Single Folder") {
    SidebarContentViewPreviewHost()
}
