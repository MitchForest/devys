// CommitHistoryView.swift
// View for displaying commit history.

import SwiftUI
import UI

/// View for displaying commit history.
@MainActor
struct CommitHistoryView: View {
    @Environment(\.devysTheme) private var theme
    @Bindable var store: GitStore
    
    @State private var selectedCommit: GitCommit?
    @State private var commitDiff: String?
    @State private var commitDiffFiles: [ParsedDiffFile] = []
    @State private var selectedDiffFileIndex: Int = 0
    @State private var isLoadingDiff: Bool = false
    
    init(store: GitStore) {
        self.store = store
    }
    
    var body: some View {
        HSplitView {
            // Commit list
            commitListView
                .frame(minWidth: 300)
            
            // Commit detail
            commitDetailView
                .frame(minWidth: 400)
        }
        .task {
            await store.loadCommitHistory()
        }
    }
    
    // MARK: - Commit List
    
    private var commitListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Commits")
                    .font(.headline)
                
                Spacer()
                
                if store.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.commits) { commit in
                        commitRow(commit)
                    }
                }
            }
        }
    }
    
    private func commitRow(_ commit: GitCommit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Commit graph dot
            Circle()
                .fill(theme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text(commit.authorName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text(commit.relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selectedCommit?.id == commit.id ? theme.accentMuted : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCommit = commit
            Task { await loadCommitDiff(commit) }
        }
    }
    
    // MARK: - Commit Detail
    
    private var commitDetailView: some View {
        Group {
            if let commit = selectedCommit {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    commitHeader(commit)
                    
                    Divider()
                    
                    // Diff
                    if isLoadingDiff {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !commitDiffFiles.isEmpty {
                        commitDiffView
                    } else if let diff = commitDiff {
                        ScrollView {
                            Text(diff)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    } else {
                        Text("Failed to load diff")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                emptyStateView
            }
        }
    }
    
    private func commitHeader(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Subject
            Text(commit.subject)
                .font(.system(size: 14, weight: .semibold))
            
            // Full message if different from subject
            if commit.message != commit.subject {
                Text(commit.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            // Metadata
            HStack(spacing: 12) {
                // Hash
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 10))
                    Text(commit.shortHash)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                
                // Author
                HStack(spacing: 4) {
                    Image(systemName: "person")
                        .font(.system(size: 10))
                    Text(commit.authorName)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                
                // Date
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(commit.relativeDate)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("Select a Commit")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Choose a commit to view its changes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func loadCommitDiff(_ commit: GitCommit) async {
        isLoadingDiff = true
        commitDiff = await store.showCommit(commit)
        commitDiffFiles = commitDiff.map(DiffFileParser.parseFiles) ?? []
        selectedDiffFileIndex = 0
        isLoadingDiff = false
    }

    private var commitDiffView: some View {
        VStack(spacing: 0) {
            commitDiffFilePicker
            Divider()
            if selectedDiffFileIndex < commitDiffFiles.count {
                let file = commitDiffFiles[selectedDiffFileIndex]
                MetalDiffView(
                    diff: file.diff,
                    filePath: file.filePath,
                    mode: .unified,
                    configuration: DiffRenderConfiguration(
                        fontName: "Menlo",
                        fontSize: 12,
                        showLineNumbers: true,
                        showPrefix: true,
                        showWordDiff: true,
                        wrapLines: false,
                        changeStyle: .fullBackground,
                        showsHunkHeaders: true
                    ),
                    isStaged: false
                )
            } else {
                Text("No diff available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var commitDiffFilePicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if commitDiffFiles.indices.contains(selectedDiffFileIndex) {
                Text(commitDiffFiles[selectedDiffFileIndex].filePath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Select a file")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("File", selection: $selectedDiffFileIndex) {
                ForEach(commitDiffFiles.indices, id: \.self) { index in
                    Text(commitDiffFiles[index].filePath).tag(index)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
