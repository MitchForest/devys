// CreatePRSheet.swift
// Sheet for creating new pull requests.

import SwiftUI
import UI

/// Sheet for creating new pull requests.
@MainActor
public struct CreatePRSheet: View {
    @Environment(\.devysTheme) private var theme
    @Bindable var store: GitStore
    let onCreated: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var baseBranch: String = "main"
    @State private var isDraft: Bool = false
    @State private var branches: [GitBranch] = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    
    @FocusState private var isTitleFocused: Bool
    
    public init(store: GitStore, onCreated: @escaping (Int) -> Void) {
        self.store = store
        self.onCreated = onCreated
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Form
            formContent
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 500, height: 500)
        .task {
            branches = await store.loadBranches()
            isTitleFocused = true
        }
        .alert("Failed to Create PR", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("Create Pull Request")
                .font(.headline)
            
            Spacer()
            
            if let branch = store.repoInfo?.currentBranch {
                HStack(spacing: 4) {
                    Text(branch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.accent)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    
                    Text(baseBranch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Form
    
    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Base branch picker
                baseBranchPicker
                
                // Title field
                titleField
                
                // Body field
                bodyField
                
                // Options
                optionsView
            }
            .padding(20)
        }
    }
    
    private var baseBranchPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Base Branch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            Picker("Base Branch", selection: $baseBranch) {
                ForEach(localBranchNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
    
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("PR title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
        }
    }
    
    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextEditor(text: $bodyText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                .frame(height: 150)
        }
    }
    
    private var optionsView: some View {
        Toggle("Create as draft", isOn: $isDraft)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button(action: createPR) {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Text(isDraft ? "Create Draft PR" : "Create Pull Request")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate || isCreating)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Computed
    
    private var localBranchNames: [String] {
        branches
            .filter { !$0.isRemote }
            .map(\.name)
            .sorted()
    }
    
    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Actions
    
    private func createPR() {
        guard canCreate else { return }
        
        isCreating = true
        
        Task {
            do {
                let prNumber = try await store.createPR(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: bodyText,
                    base: baseBranch,
                    draft: isDraft
                )
                onCreated(prNumber)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isCreating = false
        }
    }
}
