// SidebarContentView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI

/// The expandable sidebar content showing workspace files for a single folder.
///
/// Tab opening behavior (VS Code-style):
/// - Single click: Opens in preview tab (reusable) via `onPreviewFile`
/// - Double click: Opens in permanent tab via `onOpenFile`
struct SidebarContentView: View {
    @Environment(\.devysTheme) private var theme

    // MARK: - Properties

    let windowState: WindowState
    let onPreviewFile: (URL) -> Void   // Single-click: preview tab
    let onOpenFile: (URL) -> Void      // Double-click: permanent tab
    let onOpenFolder: () -> Void
    let onAddToChat: ((URL) -> Void)?  // Context menu: add file to chat

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Header
                sidebarHeader

                // Content area
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Right border connecting to top bar
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
        .background(theme.surface)
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack {
            Text("EXPLORER")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Button(action: onOpenFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Open Folder (Cmd+O)")
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.vertical, DevysSpacing.space2)
    }

    @ViewBuilder
    private var contentArea: some View {
        if let folder = windowState.folder {
            SingleFolderTreeView(
                folder: folder,
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
    @Environment(AppContainer.self) private var container

    let folder: URL
    let onPreviewFile: (URL) -> Void   // Single-click
    let onOpenFile: (URL) -> Void       // Double-click
    let onAddToChat: ((URL) -> Void)?   // Context menu: add to chat

    @State private var model: FileTreeModel?

    var body: some View {
        Group {
            if let model = model {
                FileTreeView(
                    model: model,
                    onPreviewFile: onPreviewFile,
                    onOpenFile: onOpenFile,
                    onAddToChat: onAddToChat
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            model = container.makeFileTreeModel(rootURL: folder)
        }
        .onChange(of: folder) { _, newFolder in
            model = container.makeFileTreeModel(rootURL: newFolder)
        }
    }
}

// MARK: - Preview

#Preview("Single Folder") {
    @Previewable @State var state = WindowState()
    let container = AppContainer()
    state.openFolder(URL(fileURLWithPath: "/Users/test/Code/devys"))

    return SidebarContentView(
        windowState: state,
        onPreviewFile: { _ in },
        onOpenFile: { _ in },
        onOpenFolder: {},
        onAddToChat: { _ in }
    )
    .frame(width: 240, height: 400)
    .environment(container)
    .environment(container.appSettings)
    .environment(container.recentFoldersService)
    .environment(container.layoutPersistenceService)
    .environment(\.devysTheme, DevysTheme(isDark: false))
}
