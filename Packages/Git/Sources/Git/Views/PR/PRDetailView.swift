// PRDetailView.swift
// View for displaying PR details and files.

import SwiftUI
import UI

/// View for displaying PR details and files.
@MainActor
struct PRDetailView: View {
    @Environment(\.devysTheme) private var theme
    @Bindable var store: GitStore
    
    @State private var showWordDiff: Bool = true
    @State private var showingMergeSheet: Bool = false
    
    @Environment(\.openURL) private var openURL
    
    init(store: GitStore) {
        self.store = store
    }
    
    var body: some View {
        HSplitView {
            // File list
            fileListView
                .frame(minWidth: 250)
            
            // File diff
            fileDiffView
                .frame(minWidth: 400)
        }
        .sheet(isPresented: $showingMergeSheet) {
            if let pr = store.selectedPR {
                MergeSheet(store: store, pr: pr)
            }
        }
    }
    
    // MARK: - File List
    
    private var fileListView: some View {
        VStack(spacing: 0) {
            // PR header
            if let pr = store.selectedPR {
                prHeaderView(pr)
            }
            
            Divider()
            
            // Files
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.prFiles) { file in
                        fileRow(file)
                    }
                }
            }
            
            Divider()
            
            // Actions
            if let pr = store.selectedPR {
                prActionsView(pr)
            }
        }
    }
    
    private func prHeaderView(_ pr: PullRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(pr.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            
            // Branch info
            HStack(spacing: 4) {
                Text(pr.headBranch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                
                Text(pr.baseBranch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            // Stats
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 9))
                    Text("\(pr.changedFiles) files")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Text("+\(pr.additions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                    
                    Text("-\(pr.deletions)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
    }
    
    private func fileRow(_ file: PRFile) -> some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: fileStatusIcon(file.status))
                .font(.system(size: 10))
                .foregroundStyle(fileStatusColor(file.status))
                .frame(width: 14)
            
            // Filename
            Text(file.filename)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // Stats
            HStack(spacing: 4) {
                if file.additions > 0 {
                    Text("+\(file.additions)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                }
                
                if file.deletions > 0 {
                    Text("-\(file.deletions)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(store.selectedPRFile?.id == file.id ? theme.accentMuted : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectPRFile(file)
        }
    }
    
    private func fileStatusIcon(_ status: PRFileStatus) -> String {
        switch status {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .copied: return "doc.on.doc.fill"
        }
    }
    
    private func fileStatusColor(_ status: PRFileStatus) -> Color {
        switch status {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return DevysColors.error
        case .renamed: return DevysColors.darkTextSecondary  // Neutral
        case .copied: return .purple
        }
    }
    
    private func prActionsView(_ pr: PullRequest) -> some View {
        HStack(spacing: 8) {
            // Checkout
            Button {
                Task { await store.checkoutPR(pr) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("Checkout")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // Open in browser
            Button {
                Task {
                    if let url = await store.prURL(pr) {
                        openURL(url)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open in Browser")
            
            Spacer()
            
            // Merge (only for open PRs)
            if pr.state == .open {
                Button {
                    showingMergeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 10))
                        Text("Merge")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
    }
    
    // MARK: - File Diff
    
    private var fileDiffView: some View {
        VStack(spacing: 0) {
            // Toolbar
            if let file = store.selectedPRFile {
                fileToolbar(file)
                Divider()
            }
            
            // Diff content
            if let diff = store.selectedPRFileDiff, diff.hasChanges {
                MetalDiffView(
                    diff: diff,
                    filePath: store.selectedPRFile?.path ?? "",
                    mode: .unified,
                    configuration: DiffRenderConfiguration(
                        fontName: "Menlo",
                        fontSize: 12,
                        showLineNumbers: true,
                        showPrefix: true,
                        showWordDiff: showWordDiff,
                        wrapLines: false,
                        changeStyle: .fullBackground,
                        showsHunkHeaders: true
                    ),
                    isStaged: false
                )
            } else if store.selectedPRFile == nil {
                emptyStateView
            } else {
                noChangesView
            }
        }
    }
    
    private func fileToolbar(_ file: PRFile) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Text(file.path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("+\(file.additions)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)
                
                Text("-\(file.deletions)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
            }
            
            Toggle("Word Diff", isOn: $showWordDiff)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("Select a File")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Choose a file to view its changes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noChangesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green.opacity(0.6))
            
            Text("No Diff Available")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("This file has no visible changes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Merge Sheet

private struct MergeSheet: View {
    @Bindable var store: GitStore
    let pr: PullRequest
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var mergeMethod: MergeMethod = .squash
    @State private var isMerging: Bool = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Merge Pull Request")
                .font(.headline)
            
            Text("#\(pr.number): \(pr.title)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            Picker("Merge Method", selection: $mergeMethod) {
                ForEach([MergeMethod.squash, .merge, .rebase], id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.radioGroup)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: merge) {
                    if isMerging {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Merge")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isMerging)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
    
    private func merge() {
        isMerging = true
        
        Task {
            await store.mergePR(pr, method: mergeMethod)
            dismiss()
        }
    }
}
