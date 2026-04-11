// GitSidebarView.swift
// Sidebar view showing staged and unstaged changes.

import SwiftUI
import Workspace
import UI

/// Sidebar view showing staged and unstaged file changes.
///
/// Tab opening behavior (VS Code-style):
/// - Single click: Opens in preview tab (reusable) via `onPreviewDiff`
/// - Double click: Opens in permanent tab via `onOpenDiff`
@MainActor
public struct GitSidebarView: View {
    @Environment(\.devysTheme) var theme
    @Bindable var store: GitStore
    let onPreviewDiff: ((String, Bool) -> Void)?  // Single-click: preview tab
    let onOpenDiff: ((String, Bool) -> Void)?     // Double-click: permanent tab
    let onAddDiffToChat: ((String, Bool) -> Void)? // Context menu: add diff to chat
    
    @State var showingCommitSheet = false
    @State private var expandedSections: Set<String> = ["staged", "unstaged"]
    @State private var hoveredSection: String?
    
    public init(
        store: GitStore,
        onPreviewDiff: ((String, Bool) -> Void)? = nil,
        onOpenDiff: ((String, Bool) -> Void)? = nil,
        onAddDiffToChat: ((String, Bool) -> Void)? = nil
    ) {
        self.store = store
        self.onPreviewDiff = onPreviewDiff
        self.onOpenDiff = onOpenDiff
        self.onAddDiffToChat = onAddDiffToChat
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = store.errorMessage,
               !errorMessage.isEmpty {
                errorBanner(errorMessage)
            }
            
            if !store.isRepositoryAvailable {
                nonRepositoryStateView
            } else if store.isLoading && store.changes.isEmpty {
                loadingView
            } else if store.changes.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Staged changes section
                        if !store.stagedChanges.isEmpty {
                            sectionView(
                                title: "Staged Changes",
                                id: "staged",
                                files: store.stagedChanges,
                                isStaged: true
                            )
                        }
                        
                        // Unstaged changes section
                        if !store.unstagedChanges.isEmpty {
                            sectionView(
                                title: "Unstaged",
                                id: "unstaged",
                                files: store.unstagedChanges,
                                isStaged: false
                            )
                        }

                        if !store.untrackedChanges.isEmpty {
                            sectionView(
                                title: "Untracked",
                                id: "untracked",
                                files: store.untrackedChanges,
                                isStaged: false
                            )
                        }

                        if !store.ignoredChanges.isEmpty {
                            sectionView(
                                title: "Ignored",
                                id: "ignored",
                                files: store.ignoredChanges,
                                isStaged: false
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Actions footer
            actionsFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingCommitSheet) {
            CommitSheet(store: store)
        }
    }
    
    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundStyle(DevysColors.error)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
    
    // MARK: - Section View
    
    private func sectionView(
        title: String,
        id: String,
        files: [GitFileChange],
        isStaged: Bool
    ) -> some View {
        let allowsStageAll = !isStaged && files.contains { $0.status != .ignored }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: title,
                id: id,
                count: files.count,
                isStaged: isStaged,
                allowsStageAll: allowsStageAll
            )

            if expandedSections.contains(id) {
                ForEach(files) { file in
                    fileRowView(file: file, isStaged: isStaged)
                }
            }
        }
    }

    private func sectionHeader(
        title: String,
        id: String,
        count: Int,
        isStaged: Bool,
        allowsStageAll: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedSections.contains(id) {
                    expandedSections.remove(id)
                } else {
                    expandedSections.insert(id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expandedSections.contains(id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 10)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)

                Spacer()

                if hoveredSection == id {
                    sectionBulkAction(isStaged: isStaged, allowsStageAll: allowsStageAll)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? id : nil
        }
    }

    @ViewBuilder
    private func sectionBulkAction(isStaged: Bool, allowsStageAll: Bool) -> some View {
        if isStaged {
            Button("Unstage All") {
                Task { await store.unstageAll() }
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        } else if allowsStageAll {
            Button("Stage All") {
                Task { await store.stageAll() }
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
        }
    }
    
    // MARK: - File Row Builder
    
    private func fileRowView(file: GitFileChange, isStaged: Bool) -> some View {
        FileRowView(
            file: file,
            isStaged: isStaged,
            isSelected: store.selectedFilePath == file.path && store.isViewingStaged == isStaged,
            onSelect: {
                // Single-click: select file and open in preview tab
                Task<Void, Never> { await store.selectFile(file.path, isStaged: isStaged) }
                onPreviewDiff?(file.path, isStaged)
            },
            onOpen: {
                // Double-click: open in permanent tab
                onOpenDiff?(file.path, isStaged)
            },
            onAddToChat: onAddDiffToChat != nil ? {
                onAddDiffToChat?(file.path, isStaged)
            } : nil,
            onStage: isStaged || file.status == .ignored ? nil : {
                Task<Void, Never> { await store.stage(file.path) }
            },
            onUnstage: isStaged ? {
                Task<Void, Never> { await store.unstage(file.path) }
            } : nil,
            onDiscard: isStaged || file.status == .ignored ? nil : {
                Task<Void, Never> { await store.discard(file) }
            }
        )
    }
    
}

// MARK: - File Row View

private struct FileRowView: View {
    @Environment(\.devysTheme) private var theme
    
    let file: GitFileChange
    let isStaged: Bool
    let isSelected: Bool
    let onSelect: () -> Void      // Single-click: preview
    let onOpen: (() -> Void)?     // Double-click: permanent
    let onAddToChat: (() -> Void)? // Context menu: add to chat
    let onStage: (() -> Void)?
    let onUnstage: (() -> Void)?
    let onDiscard: (() -> Void)?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            Image(systemName: file.status.iconName)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
                .frame(width: 14)
            
            // Filename
            Text(file.filename)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Actions on hover
            if isHovered {
                HStack(spacing: 4) {
                    if let onStage {
                        Button {
                            onStage()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DevysColors.success)
                        }
                        .buttonStyle(.plain)
                        .help("Stage")
                    }
                    
                    if let onUnstage {
                        Button {
                            onUnstage()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DevysColors.warning)
                        }
                        .buttonStyle(.plain)
                        .help("Unstage")
                    }
                    
                    if let onDiscard {
                        Button {
                            onDiscard()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DevysColors.error)
                        }
                        .buttonStyle(.plain)
                        .help("Discard")
                    }
                }
            } else {
                // Directory path (truncated)
                if !file.directory.isEmpty && file.directory != "." {
                    Text(file.directory)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onOpen?()
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(GitDiffTransfer(path: file.path, isStaged: isStaged)) {
            // Drag preview
            HStack(spacing: 6) {
                Image(systemName: file.status.iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                Text(file.filename)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Text(isStaged ? "Staged" : "Unstaged")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .contextMenu {
            contextMenuItems
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return theme.accentMuted
        }
        if isHovered {
            return theme.hover
        }
        return Color.clear
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onOpen?()
        } label: {
            Label("View Diff", systemImage: "arrow.left.arrow.right")
        }
        
        if let onAddToChat {
            Button {
                onAddToChat()
            } label: {
                Label("Add Diff to Chat", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        
        Divider()
        
        if let onStage {
            Button {
                onStage()
            } label: {
                Label("Stage", systemImage: "plus.circle")
            }
        }
        
        if let onUnstage {
            Button {
                onUnstage()
            } label: {
                Label("Unstage", systemImage: "minus.circle")
            }
        }
        
        if let onDiscard {
            Divider()
            Button(role: .destructive) {
                onDiscard()
            } label: {
                Label("Discard Changes", systemImage: "xmark.circle")
            }
        }
    }
    
    private var statusColor: Color {
        switch file.status {
        case .modified: return DevysColors.warning
        case .added: return DevysColors.success
        case .deleted: return DevysColors.error
        case .renamed: return theme.textSecondary
        case .untracked: return theme.textSecondary
        case .unmerged: return DevysColors.error
        case .copied: return .purple
        case .ignored: return theme.textTertiary
        }
    }
}
