// BranchPicker.swift
// Branch picker and management view.

import SwiftUI
import UI

/// Branch picker and management view.
@MainActor
struct BranchPicker: View {
    @Environment(\.devysTheme) private var theme
    @Bindable var store: GitStore
    
    @State private var branches: [GitBranch] = []
    @State private var searchText: String = ""
    @State private var showingNewBranch: Bool = false
    @State private var newBranchName: String = ""
    @State private var isLoading: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var branchToDelete: GitBranch?
    
    init(store: GitStore) {
        self.store = store
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Search
            searchField
            
            // Branch list
            branchList
            
            Divider()
            
            // New branch button
            newBranchButton
        }
        .frame(width: 300)
        .task {
            await loadBranches()
        }
        .alert("Delete Branch?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let branch = branchToDelete {
                    Task { await deleteBranch(branch) }
                }
            }
        } message: {
            if let branch = branchToDelete {
                Text("Are you sure you want to delete '\(branch.name)'? This cannot be undone.")
            }
        }
        .sheet(isPresented: $showingNewBranch) {
            newBranchSheet
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("Branches")
                .font(.headline)
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
            
            Button {
                Task { await loadBranches() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Search
    
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            
            TextField("Search branches...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }
    
    // MARK: - Branch List
    
    private var branchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Local branches
                if !localBranches.isEmpty {
                    sectionHeader("Local")
                    ForEach(localBranches) { branch in
                        branchRow(branch)
                    }
                }
                
                // Remote branches
                if !remoteBranches.isEmpty {
                    sectionHeader("Remote")
                    ForEach(remoteBranches) { branch in
                        branchRow(branch)
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
    
    private func branchRow(_ branch: GitBranch) -> some View {
        HStack(spacing: 8) {
            // Current indicator
            if branch.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Color.clear
                    .frame(width: 12)
            }
            
            // Icon
            Image(systemName: branch.isRemote ? "globe" : "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            
            // Name
            Text(branch.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
            
            Spacer()
            
            // Delete button (for non-current local branches)
            if !branch.isCurrent && !branch.isRemote {
                Button {
                    branchToDelete = branch
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .opacity(0.6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(branch.isCurrent ? theme.accentMuted : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !branch.isCurrent {
                Task { await checkout(branch) }
            }
        }
    }
    
    // MARK: - New Branch
    
    private var newBranchButton: some View {
        Button {
            showingNewBranch = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                
                Text("New Branch")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var newBranchSheet: some View {
        VStack(spacing: 16) {
            Text("Create New Branch")
                .font(.headline)
            
            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") {
                    showingNewBranch = false
                    newBranchName = ""
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create") {
                    Task {
                        await createBranch()
                        showingNewBranch = false
                        newBranchName = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
    
    // MARK: - Computed Properties
    
    private var filteredBranches: [GitBranch] {
        if searchText.isEmpty {
            return branches
        }
        return branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var localBranches: [GitBranch] {
        filteredBranches.filter { !$0.isRemote }
    }
    
    private var remoteBranches: [GitBranch] {
        filteredBranches.filter { $0.isRemote }
    }
    
    // MARK: - Actions
    
    private func loadBranches() async {
        isLoading = true
        branches = await store.loadBranches()
        isLoading = false
    }
    
    private func checkout(_ branch: GitBranch) async {
        isLoading = true
        await store.checkout(branch: branch.name)
        await loadBranches()
        isLoading = false
    }
    
    private func createBranch() async {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        isLoading = true
        await store.createBranch(name: name)
        await loadBranches()
        isLoading = false
    }
    
    private func deleteBranch(_ branch: GitBranch) async {
        isLoading = true
        await store.deleteBranch(name: branch.name)
        await loadBranches()
        isLoading = false
    }
}
