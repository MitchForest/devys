// FileTreeRow.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Workspace
import UI
import AppKit

/// A single row in the file tree - terminal-style layout with tree-drawing characters.
///
/// Layout structure:
/// ```
/// [margin][tree-chars][icon][text]
/// └──4px──┘└─depth*12─┘└12px┘
/// ```
///
/// Key principles:
/// - Terminal aesthetic with monospace fonts
/// - Tree-drawing characters (├──, └──, │) for hierarchy
/// - Minimal, clean layout
/// - Full-width selection/hover backgrounds
struct FileTreeRow: View {
    @Environment(\.devysTheme) private var theme
    
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
    
    // MARK: - Layout Constants (Terminal style)
    
    /// Left margin
    private let leftMargin: CGFloat = 4
    /// Indent per depth level (monospace char width)
    private let indentPerLevel: CGFloat = 12
    /// Icon width
    private let iconWidth: CGFloat = 14
    /// Spacing between elements
    private let elementSpacing: CGFloat = 4
    /// Row height (compact terminal style)
    private let rowHeight: CGFloat = 20
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Full-width background (behind everything)
            rowBackground
            
            // Row content
            HStack(spacing: 0) {
                // Fixed left margin
                Spacer().frame(width: leftMargin)
                
                // Tree-drawing characters for depth
                treePrefix
                
                // Chevron for directories
                chevronButton
                    .frame(width: flatNode.node.isDirectory ? 12 : 0)

                if flatNode.node.isDirectory {
                    Spacer().frame(width: 2)
                }
                
                // Icon
                iconView
                    .frame(width: iconWidth)
                
                Spacer().frame(width: elementSpacing)
                
                // Name - monospace for terminal aesthetic
                Text(flatNode.node.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer(minLength: 0)

                if let gitStatusSummary,
                   !gitStatusSummary.label.isEmpty {
                    Text(gitStatusSummary.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(gitStatusColor(for: gitStatusSummary))
                }
            }
        }
        .frame(height: rowHeight)
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
            withAnimation(.easeInOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
        .draggable(flatNode.node.url) {
            // Drag preview - terminal style
            HStack(spacing: 4) {
                Image(systemName: flatNode.node.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                Text(flatNode.node.name)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .contextMenu {
            fileContextMenu
        }
    }
    
    // MARK: - Tree-Drawing Characters
    
    /// Generates tree-drawing prefix like "├── " or "└── " based on position
    @ViewBuilder
    private var treePrefix: some View {
        if flatNode.depth > 0 {
            HStack(spacing: 0) {
                // Vertical lines for parent levels
                ForEach(0..<(flatNode.depth - 1), id: \.self) { _ in
                    Text("│")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: indentPerLevel)
                }
                
                // Branch character - use └ for last item, ├ for others
                Text(flatNode.isLastChild ? "└" : "├")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                Text("─")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                Spacer().frame(width: 2)
            }
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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            // Empty space for files (maintains alignment)
            Color.clear
        }
    }
    
    // MARK: - Icon
    
    @ViewBuilder
    private var iconView: some View {
        Image(systemName: flatNode.node.icon)
            .font(.system(size: 14))
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
    
    // MARK: - Background (Full-width, VS Code style)
    
    private var rowBackground: some View {
        Group {
            if isSelected {
                // Subtle accent tint for selection
                theme.accentMuted
            } else if isHovered {
                // Very subtle hover
                Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.5)
            } else {
                Color.clear
            }
        }
    }

    private func gitStatusColor(for summary: WorkspaceFileTreeGitStatusSummary) -> Color {
        switch summary.primaryCode {
        case .modified:
            return DevysColors.warning
        case .added:
            return DevysColors.success
        case .deleted:
            return DevysColors.error
        case .renamed:
            return theme.textSecondary
        case .copied:
            return .purple
        case .untracked:
            return theme.textSecondary
        case .ignored:
            return theme.textTertiary
        case .unmerged:
            return DevysColors.error
        case .none:
            return theme.textTertiary
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
        
        // Add to Chat (only for files, not directories)
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
            // TODO: Calculate relative path from workspace root
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(flatNode.node.url.lastPathComponent, forType: .string)
        }
        
        Divider()
        
        Button("Rename...") { onRename() }
            .disabled(!canRename)
        
        Button("Delete", role: .destructive) { onDelete() }
    }
}
