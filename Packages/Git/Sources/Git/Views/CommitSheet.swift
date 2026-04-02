// CommitSheet.swift
// Sheet for composing commit messages.

import SwiftUI
import UI

/// Sheet for composing and submitting commits.
@MainActor
struct CommitSheet: View {
    @Bindable var store: GitStore
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var message: String = ""
    @State private var extendedMessage: String = ""
    @State private var pushAfterCommit: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isCommitting: Bool = false
    
    @FocusState private var isMessageFocused: Bool
    
    init(store: GitStore) {
        self.store = store
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Staged files summary
                stagedFilesSummary
                
                // Subject line
                subjectLineField
                
                // Extended message
                extendedMessageField
                
                // Options
                optionsView
            }
            .padding(20)
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(width: 500, height: 450)
        .onAppear {
            isMessageFocused = true
        }
        .alert("Commit Failed", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("Commit Changes")
                .font(.headline)
            
            Spacer()
            
            if let branch = store.repoInfo?.currentBranch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text(branch)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Staged Files Summary
    
    private var stagedFilesSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Staged Changes (\(store.stagedChanges.count))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.stagedChanges.prefix(10)) { file in
                        HStack(spacing: 4) {
                            Image(systemName: file.status.iconName)
                                .font(.system(size: 9))
                                .foregroundStyle(statusColor(file.status))
                            
                            Text(file.filename)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    if store.stagedChanges.count > 10 {
                        Text("+\(store.stagedChanges.count - 10) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    
    // MARK: - Subject Line
    
    private var subjectLineField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Subject")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(message.count)/72")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(message.count > 72 ? Color.orange : Color.secondary.opacity(0.6))
            }
            
            TextField("Brief description of changes", text: $message)
                .textFieldStyle(.roundedBorder)
                .focused($isMessageFocused)
                .onSubmit {
                    if canCommit {
                        commit()
                    }
                }
        }
    }
    
    // MARK: - Extended Message
    
    private var extendedMessageField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extended Description (optional)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextEditor(text: $extendedMessage)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(height: 100)
        }
    }
    
    // MARK: - Options
    
    private var optionsView: some View {
        Toggle("Push after committing", isOn: $pushAfterCommit)
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
            
            Button(action: commit) {
                if isCommitting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Text(pushAfterCommit ? "Commit & Push" : "Commit")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCommit || isCommitting)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Actions
    
    private var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !store.stagedChanges.isEmpty
    }
    
    private func commit() {
        guard canCommit else { return }
        
        isCommitting = true
        
        let fullMessage: String
        if extendedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullMessage = message
        } else {
            fullMessage = message + "\n\n" + extendedMessage
        }
        
        Task {
            do {
                try await store.commit(message: fullMessage, push: pushAfterCommit)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isCommitting = false
        }
    }
    
    private func statusColor(_ status: GitFileStatus) -> Color {
        switch status {
        case .modified: return .orange
        case .added: return DevysColors.success
        case .deleted: return DevysColors.error
        case .renamed: return DevysColors.darkTextSecondary  // Neutral
        default: return DevysColors.darkTextSecondary
        }
    }
}
