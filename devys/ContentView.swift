//
//  ContentView.swift
//  devys
//
//  Main application view with three-column layout.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(ProcessManager.self) private var processManager
    
    // MARK: - Queries
    
    @Query(sort: \Workspace.lastAccessedAt, order: .reverse)
    private var workspaces: [Workspace]
    
    // MARK: - State
    
    @State private var selectedWorkspace: Workspace?
    @State private var selectedThread: Thread?
    @State private var session: ProcessSession?
    @State private var showAddWorkspace = false
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                workspaces: workspaces,
                threads: session?.threads ?? [],
                selectedWorkspace: $selectedWorkspace,
                selectedThread: $selectedThread,
                onAddWorkspace: { showAddWorkspace = true },
                onNewConversation: { type in startNewSession(type: type) }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } content: {
            if let session {
                ConversationView(session: session)
            } else if let workspace = selectedWorkspace {
                SelectAgentView(
                    workspace: workspace,
                    onSelect: { type in startNewSession(type: type) }
                )
            } else {
                WelcomeView(onAddWorkspace: { showAddWorkspace = true })
            }
        } detail: {
            InspectorPlaceholder()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 320)
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar(id: "devys") {
            DevysToolbar(
                session: session,
                onToggleSidebar: toggleSidebar,
                onShowSettings: { showSettings = true }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAddWorkspace) {
            AddWorkspaceSheet { url in
                addWorkspace(url: url)
            }
        }
        .onChange(of: selectedWorkspace) { _, workspace in
            Task { await selectWorkspace(workspace) }
        }
        .onChange(of: selectedThread) { _, thread in
            Task {
                if let thread, let session {
                    await session.selectThread(thread)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addWorkspace)) { _ in
            showAddWorkspace = true
        }
    }
    
    // MARK: - Actions
    
    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .all ? .doubleColumn : .all
        }
    }
    
    private func addWorkspace(url: URL) {
        let workspace = Workspace(url: url)
        modelContext.insert(workspace)
        selectedWorkspace = workspace
        try? modelContext.save()
    }
    
    private func selectWorkspace(_ workspace: Workspace?) async {
        // Stop current session
        if let session {
            await processManager.stop(session)
        }
        
        guard let workspace else {
            session = nil
            return
        }
        
        // Create new session (default to codex)
        let newSession = processManager.session(workspacePath: workspace.path, agentType: .codex)
        session = newSession
        
        do {
            try await processManager.start(newSession)
        } catch {
            newSession.error = ProcessError(code: "START_FAILED", message: error.localizedDescription)
        }
    }
    
    private func startNewSession(type: AgentType) {
        guard let workspace = selectedWorkspace else { return }
        
        Task {
            // Stop current session
            if let session {
                await processManager.stop(session)
            }
            
            // Create new session with selected type
            let newSession = processManager.session(workspacePath: workspace.path, agentType: type)
            session = newSession
            selectedThread = nil
            
            do {
                try await processManager.start(newSession)
            } catch {
                newSession.error = ProcessError(code: "START_FAILED", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Toolbar

struct DevysToolbar: CustomizableToolbarContent {
    let session: ProcessSession?
    let onToggleSidebar: () -> Void
    let onShowSettings: () -> Void
    
    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "sidebar", placement: .navigation) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }
        
        ToolbarItem(id: "workspace", placement: .principal) {
            if let session {
                HStack(spacing: 8) {
                    StatusIndicator(state: session.connectionState)
                    Text(URL(fileURLWithPath: session.workspacePath).lastPathComponent)
                        .fontWeight(.medium)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Image(systemName: session.agentType.icon)
                        .font(.caption)
                }
            } else {
                EmptyView()
            }
        }
        
        ToolbarItem(id: "settings", placement: .primaryAction) {
            Button(action: onShowSettings) {
                Image(systemName: "gear")
            }
            .help("Settings")
        }
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let state: ProcessState
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForState(state))
                .frame(width: 8, height: 8)
            
            if case .connecting = state {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }
    
    private func colorForState(_ state: ProcessState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Placeholder Views

struct WelcomeView: View {
    let onAddWorkspace: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("Welcome to Devys")
                .font(.largeTitle.bold())
            
            Text("An agent-native IDE for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Spacer().frame(height: 20)
            
            Button(action: onAddWorkspace) {
                Label("Add Workspace", systemImage: "folder.badge.plus")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Text("Add a project folder to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InspectorPlaceholder: View {
    var body: some View {
        VStack {
            Text("Inspector")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Coming in later milestones")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SelectAgentView: View {
    let workspace: Workspace
    let onSelect: (AgentType) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Start a Conversation")
                .font(.title2.bold())
            
            Text("Choose an AI to work with in \(workspace.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            HStack(spacing: 12) {
                Button { onSelect(.codex) } label: {
                    Label("Codex", systemImage: "cpu")
                }
                .buttonStyle(.borderedProminent)
                
                Button { onSelect(.claudeCode) } label: {
                    Label("Claude Code", systemImage: "brain")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Add Workspace Sheet

struct AddWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (URL) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("Add Workspace")
                .font(.title2.bold())
            
            Text("Select a project folder to add as a workspace")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                
                Button("Choose Folder...") { selectFolder() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        panel.prompt = "Add Workspace"
        
        if panel.runModal() == .OK, let url = panel.url {
            onAdd(url)
            dismiss()
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let addWorkspace = Notification.Name("addWorkspace")
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(ProcessManager())
        .modelContainer(for: Workspace.self, inMemory: true)
}
