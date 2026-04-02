// ContentView+Sidebar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Git

extension ContentView {
    @ViewBuilder
    var sidebarContent: some View {
        switch activeSidebarItem {
        case .files:
            SidebarContentView(
                windowState: windowState,
                onPreviewFile: { url in openInPreviewTab(content: .editor(url: url)) },
                onOpenFile: { url in openInPermanentTab(content: .editor(url: url)) },
                onOpenFolder: { requestOpenFolder() },
                onAddToChat: nil
            )
        case .git:
            if let store = gitStore {
                GitSidebarView(
                    store: store,
                    onPreviewDiff: { path, isStaged in
                        openInPreviewTab(content: .gitDiff(path: path, isStaged: isStaged))
                    },
                    onOpenDiff: { path, isStaged in
                        openInPermanentTab(content: .gitDiff(path: path, isStaged: isStaged))
                    },
                    onAddDiffToChat: nil
                )
            } else {
                PlaceholderSidebarView(title: "Git", icon: "arrow.triangle.branch")
            }
        case .agents:
            PlaceholderSidebarView(title: "Agents", icon: "cpu")
        default:
            EmptyView()
        }
    }
}
