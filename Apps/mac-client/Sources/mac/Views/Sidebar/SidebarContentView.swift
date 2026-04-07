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
    let showsTrailingBorder: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsTrailingBorder {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(width: 1)
            }
        }
        .background(theme.surface)
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
                onAddToChat: onAddToChat
            )
        } else {
            EmptyView()
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

    var body: some View {
        Group {
            if let model = model {
                FileTreeView(
                    model: model,
                    gitStatusIndex: gitStatusIndex,
                    onPreviewFile: onPreviewFile,
                    onOpenFile: onOpenFile,
                    onAddToChat: onAddToChat
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: folder) {
            await model?.loadTreeIfNeeded()
        }
    }
}

// MARK: - Preview

#Preview("Single Folder") {
    @Previewable @State var state = WindowState()
    let container = AppContainer()
    state.openRepository(URL(fileURLWithPath: "/Users/test/Code/devys"))

    return SidebarContentView(
        model: nil,
        activeDirectory: state.selectedRepositoryRootURL,
        gitStatusIndex: nil,
        onPreviewFile: { _ in },
        onOpenFile: { _ in },
        onAddToChat: { _ in },
        showsTrailingBorder: true
    )
    .frame(width: 240, height: 400)
    .environment(container)
    .environment(container.appSettings)
    .environment(container.recentRepositoriesService)
    .environment(container.layoutPersistenceService)
    .environment(\.devysTheme, DevysTheme(isDark: false))
}
