// GitPanelView.swift
// Main panel view for Git integration.

import SwiftUI

/// Main panel view for Git integration.
/// This is the primary entry point for embedding Git in a Devys panel.
@MainActor
public struct GitPanelView: View {
    @Bindable var store: GitStore
    
    @State private var selectedTab: GitTab = .changes
    
    enum GitTab: String, CaseIterable {
        case changes = "Changes"
        case history = "History"
        case prs = "Pull Requests"
    }
    
    public init(store: GitStore) {
        self.store = store
    }
    
    public var body: some View {
        HSplitView {
            // Sidebar
            sidebarView
                .frame(minWidth: 220, maxWidth: 350)
            
            // Main content
            mainContentView
        }
        .task {
            store.startWatching()
            await store.refresh()
            await store.checkPRAvailability()
        }
        .onDisappear {
            store.stopPolling()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Tab picker
            tabPicker
            
            Divider()
            
            // Tab content
            tabSidebar
        }
    }
    
    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(GitTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var tabSidebar: some View {
        switch selectedTab {
        case .changes:
            GitSidebarView(store: store)
        case .history:
            historySidebar
        case .prs:
            PRListView(store: store)
        }
    }
    
    private var historySidebar: some View {
        VStack(spacing: 0) {
            // Branch picker
            HStack {
                Text("Branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Menu {
                    BranchPicker(store: store)
                } label: {
                    HStack(spacing: 4) {
                        Text(store.repoInfo?.currentBranch ?? "Unknown")
                            .font(.system(size: 11))
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Commits
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.commits) { commit in
                        commitRow(commit)
                    }
                }
            }
        }
        .task {
            await store.loadCommitHistory()
        }
    }
    
    private func commitRow(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject)
                .font(.system(size: 11))
                .lineLimit(1)
            
            HStack(spacing: 4) {
                Text(commit.shortHash)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.tertiary)
                
                Text(commit.relativeDate)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContentView: some View {
        switch selectedTab {
        case .changes:
            GitDiffView(store: store)
                .keyboardShortcuts()
        case .history:
            CommitHistoryView(store: store)
        case .prs:
            if store.isShowingPRDetail {
                PRDetailView(store: store)
            } else {
                prEmptyState
            }
        }
    }
    
    private var prEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("Select a Pull Request")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Choose a PR from the sidebar to view its details.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Convenience Initializer

public extension GitPanelView {
    /// Create a panel view for a workspace.
    static func forWorkspace(
        id: UUID,
        projectFolder: URL?
    ) -> GitPanelView {
        let store = GitStoreRegistry.shared.store(
            for: id,
            projectFolder: projectFolder
        )
        return GitPanelView(store: store)
    }
}
