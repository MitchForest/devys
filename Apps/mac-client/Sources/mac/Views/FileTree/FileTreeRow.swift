// FileTreeRow.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI
import AppKit

/// A single row in the file tree with connector-line indentation and visual git status.
///
/// Layout structure:
/// ```
/// [connector-lines][chevron][icon][name]...[git-status]
/// ```
struct FileTreeRow: View {
    @Environment(\.devysTheme) private var theme
    @Environment(\.densityLayout) private var layout

    // MARK: - Properties

    let flatNode: FlatFileNode
    let gitStatusSummary: WorkspaceFileTreeGitStatusSummary?
    let isSelected: Bool
    let canRename: Bool
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onToggleExpand: () -> Void
    let onOpenFile: () -> Void
    let onAddToChat: ((URL) -> Void)?
    let onRename: () -> Void
    let onDelete: () -> Void

    init(
        flatNode: FlatFileNode,
        gitStatusSummary: WorkspaceFileTreeGitStatusSummary? = nil,
        isSelected: Bool,
        canRename: Bool = true,
        onSelect: @escaping (NSEvent.ModifierFlags) -> Void,
        onToggleExpand: @escaping () -> Void,
        onOpenFile: @escaping () -> Void,
        onAddToChat: ((URL) -> Void)? = nil,
        onRename: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.flatNode = flatNode
        self.gitStatusSummary = gitStatusSummary
        self.isSelected = isSelected
        self.canRename = canRename
        self.onSelect = onSelect
        self.onToggleExpand = onToggleExpand
        self.onOpenFile = onOpenFile
        self.onAddToChat = onAddToChat
        self.onRename = onRename
        self.onDelete = onDelete
    }

    @State private var isHovered = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .leading) {
            rowBackground

            HStack(spacing: 0) {
                // Connector lines for depth
                if flatNode.depth > 0 {
                    ConnectorLine(
                        depth: flatNode.depth,
                        isLast: flatNode.isLastChild,
                        hasChildren: flatNode.node.isDirectory
                    )
                }

                // Chevron for directories
                chevronButton
                    .frame(width: flatNode.node.isDirectory ? 14 : 0)

                if flatNode.node.isDirectory {
                    Spacer().frame(width: Spacing.space1)
                }

                // Icon
                iconView
                    .frame(width: 16)

                Spacer().frame(width: Spacing.space1)

                // Name — proportional font for fast scanning
                Text(flatNode.node.name)
                    .font(Typography.body)
                    .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                // Git status indicator (visual symbols instead of text labels)
                if let gitStatus = mappedGitStatus {
                    GitStatusIndicator(gitStatus)
                        .padding(.trailing, Spacing.space1)
                }
            }
            .padding(.leading, Spacing.space1)
            .padding(.trailing, Spacing.space2)
        }
        .frame(height: layout.sidebarRowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            onSelect(modifiers)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !flatNode.node.isDirectory {
                    onOpenFile()
                }
            }
        )
        .onHover { hovering in
            withAnimation(Animations.micro) {
                isHovered = hovering
            }
        }
        .draggable(flatNode.node.url) {
            HStack(spacing: Spacing.space1) {
                Image(systemName: flatNode.node.icon)
                    .font(Typography.label)
                    .foregroundStyle(iconColor)
                Text(flatNode.node.name)
                    .font(Typography.label)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.space1)
            .background(theme.overlay, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        }
        .contextMenu {
            fileContextMenu
        }
    }

    // MARK: - Chevron

    @ViewBuilder
    private var chevronButton: some View {
        if flatNode.node.isDirectory {
            Button {
                onToggleExpand()
            } label: {
                Image(systemName: flatNode.isExpanded ? "chevron.down" : "chevron.right")
                    .font(Typography.micro.weight(.medium))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        Image(systemName: flatNode.node.icon)
            .font(Typography.body)
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        switch flatNode.node.iconColor {
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .cyan: return .cyan
        case .red: return .red
        case .purple: return .purple
        case .secondary: return .secondary
        case .tertiary: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    // MARK: - Background

    private var rowBackground: some View {
        Group {
            if isSelected {
                theme.accentMuted
            } else if isHovered {
                theme.hover
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Git Status Mapping

    /// Maps the workspace git status code to the UI package's GitFileStatus enum.
    private var mappedGitStatus: GitFileStatus? {
        guard let code = gitStatusSummary?.primaryCode else { return nil }
        switch code {
        case .added, .untracked: return .new
        case .modified: return .modified
        case .deleted: return .deleted
        case .renamed, .copied: return .renamed
        case .unmerged: return .conflict
        case .ignored: return .ignored
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var fileContextMenu: some View {
        if flatNode.node.isDirectory {
            Button("New File...") { /* TODO */ }
            Button("New Folder...") { /* TODO */ }
            Divider()
        }

        if !flatNode.node.isDirectory, let onAddToChat {
            Button {
                onAddToChat(flatNode.node.url)
            } label: {
                Label("Add to Chat", systemImage: "bubble.left.and.text.bubble.right")
            }

            Divider()
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(
                flatNode.node.url.path,
                inFileViewerRootedAtPath: flatNode.node.url.deletingLastPathComponent().path
            )
        }

        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(flatNode.node.url.path, forType: .string)
        }

        Button("Copy Relative Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(flatNode.node.url.lastPathComponent, forType: .string)
        }

        Divider()

        Button("Rename...") { onRename() }
            .disabled(!canRename)

        Button("Delete", role: .destructive) { onDelete() }
    }
}
