//
//  SidebarView.swift
//  devys
//
//  Left sidebar with workspaces and threads.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    // MARK: - Properties
    
    let workspaces: [Workspace]
    let threads: [Thread]
    @Binding var selectedWorkspace: Workspace?
    @Binding var selectedThread: Thread?
    let onAddWorkspace: () -> Void
    let onNewConversation: (AgentType) -> Void
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Body
    
    var body: some View {
        List(selection: $selectedThread) {
            // Workspaces section
            Section {
                ForEach(workspaces) { workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        isSelected: workspace.id == selectedWorkspace?.id
                    )
                    .onTapGesture {
                        selectedWorkspace = workspace
                        selectedThread = nil
                        workspace.touch()
                    }
                    .contextMenu {
                        workspaceContextMenu(for: workspace)
                    }
                }
            } header: {
                HStack {
                    Text("Workspaces")
                    Spacer()
                    Button(action: onAddWorkspace) {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Threads section (for selected workspace)
            if selectedWorkspace != nil {
                Section {
                    if threads.isEmpty {
                        Text("No conversations yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(threads) { thread in
                            ThreadRow(thread: thread)
                                .tag(thread)
                        }
                    }
                } header: {
                    HStack {
                        Text("Conversations")
                        Spacer()
                        Menu {
                            Button {
                                onNewConversation(.codex)
                            } label: {
                                Label("Codex", systemImage: "cpu")
                            }
                            Button {
                                onNewConversation(.claudeCode)
                            } label: {
                                Label("Claude Code", systemImage: "brain")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }
    
    // MARK: - Context Menus
    
    @ViewBuilder
    private func workspaceContextMenu(for workspace: Workspace) -> some View {
        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.path)
        }
        
        Menu("New Conversation") {
            Button {
                selectedWorkspace = workspace
                onNewConversation(.codex)
            } label: {
                Label("Codex", systemImage: "cpu")
            }
            Button {
                selectedWorkspace = workspace
                onNewConversation(.claudeCode)
            } label: {
                Label("Claude Code", systemImage: "brain")
            }
        }
        
        Divider()
        
        Button("Remove Workspace", role: .destructive) {
            removeWorkspace(workspace)
        }
    }
    
    // MARK: - Actions
    
    private func removeWorkspace(_ workspace: Workspace) {
        if selectedWorkspace?.id == workspace.id {
            selectedWorkspace = nil
            selectedThread = nil
        }
        modelContext.delete(workspace)
        try? modelContext.save()
    }
}

// MARK: - Workspace Row

struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(isSelected ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Thread Row

struct ThreadRow: View {
    let thread: Thread
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .foregroundStyle(.secondary)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayTitle)
                    .lineLimit(1)
                
                Text(thread.lastMessageAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            if thread.messageCount > 0 {
                Text("\(thread.messageCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    SidebarView(
        workspaces: [],
        threads: [],
        selectedWorkspace: .constant(nil),
        selectedThread: .constant(nil),
        onAddWorkspace: {},
        onNewConversation: { _ in }
    )
}
