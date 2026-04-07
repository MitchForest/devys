// GitDiffView.swift
// Main diff view with unified/split mode support.

import SwiftUI
import UI

/// Main diff view for displaying file changes.
@MainActor
public struct GitDiffView: View {
    @Bindable var store: GitStore
    
    @State private var showWordDiff = true
    @State private var showLineNumbers = true
    @State private var wrapLines = false
    @State private var changeStyle: DiffChangeStyle = .fullBackground
    
    public init(store: GitStore) {
        self.store = store
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView
            
            Divider()
            
            // Content
            if let diff = store.selectedDiff {
                if diff.isBinary {
                    binaryFileView
                } else if !diff.hasChanges {
                    noChangesView
                } else {
                    diffContentView(diff: diff)
                }
            } else if store.isLoading {
                loadingView
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // File path
            if let path = store.selectedFilePath {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Text(path)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            // Stats
            if let diff = store.selectedDiff, diff.hasChanges {
                HStack(spacing: 8) {
                    Text("+\(diff.totalAdded)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DevysColors.success)

                    Text("-\(diff.totalRemoved)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DevysColors.error)
                }
            }
            
            Divider()
                .frame(height: 16)
            
            // View mode toggle
            Picker("View Mode", selection: $store.diffViewMode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 100)
            
            // Options menu
            Menu {
                Toggle("Word Diff", isOn: $showWordDiff)
                Toggle("Line Numbers", isOn: $showLineNumbers)
                Toggle("Wrap Lines", isOn: $wrapLines)
                
                Toggle("Ignore Whitespace", isOn: Binding(
                    get: { store.ignoreWhitespace },
                    set: { _ in
                        Task { await store.toggleIgnoreWhitespace() }
                    }
                ))

                Picker("Change Style", selection: $changeStyle) {
                    ForEach(DiffChangeStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                
                Divider()
                
                Button("Expand Context") {
                    Task { await store.increaseContext() }
                }
                
                Button("Show All Context") {
                    Task { await store.showAllContext() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Diff Content
    
    @ViewBuilder
    private func diffContentView(diff: DiffSnapshot) -> some View {
        MetalDiffView(
            snapshot: diff,
            filePath: store.selectedFilePath ?? "",
            mode: store.diffViewMode,
            configuration: DiffRenderConfiguration(
                fontName: "Menlo",
                fontSize: 12,
                showLineNumbers: showLineNumbers,
                showPrefix: true,
                showWordDiff: showWordDiff,
                wrapLines: wrapLines,
                changeStyle: changeStyle,
                showsHunkHeaders: false
            ),
            isStaged: store.isViewingStaged,
            focusedHunkIndex: store.focusedHunkIndex,
            onAcceptHunk: { index in
                await store.acceptHunk(at: index)
            },
            onRejectHunk: { index in
                await store.rejectHunk(at: index)
            }
        )
    }
    
    // MARK: - Empty States
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading diff...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("Select a File")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Choose a file from the sidebar to view its diff.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var binaryFileView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            
            Text("Binary File")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("This file is binary and cannot be displayed as a diff.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var noChangesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(DevysColors.success.opacity(0.6))
            
            Text("No Changes")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("This file has no changes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Keyboard Shortcuts

extension GitDiffView {
    /// Add keyboard navigation and accept/reject shortcuts.
    func keyboardShortcuts() -> some View {
        self
            .onKeyPress(.downArrow) {
                store.nextHunk()
                return .handled
            }
            .onKeyPress(.upArrow) {
                store.previousHunk()
                return .handled
            }
            .onKeyPress(KeyEquivalent("j")) {
                store.nextHunk()
                return .handled
            }
            .onKeyPress(KeyEquivalent("k")) {
                store.previousHunk()
                return .handled
            }
            .onKeyPress(KeyEquivalent("n")) {
                Task { await store.nextFile() }
                return .handled
            }
            .onKeyPress(KeyEquivalent("p")) {
                Task { await store.previousFile() }
                return .handled
            }
            // Accept/Reject shortcuts
            .onKeyPress(KeyEquivalent("a")) {
                Task { await store.acceptFocusedHunk() }
                return .handled
            }
            .onKeyPress(KeyEquivalent("r")) {
                Task { await store.rejectFocusedHunk() }
                return .handled
            }
    }
}
