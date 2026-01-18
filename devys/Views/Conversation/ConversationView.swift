//
//  ConversationView.swift
//  devys
//
//  Main conversation view with message list and composer.
//  Observes ProcessSession directly - no intermediate layer.
//

import SwiftUI

struct ConversationView: View {
    
    // MARK: - Model
    
    /// The session to observe directly.
    let session: ProcessSession
    
    // MARK: - Environment
    
    @Environment(ProcessManager.self) private var processManager
    
    // MARK: - State
    
    @State private var scrollProxy: ScrollViewProxy?
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ConversationHeaderView(
                workspacePath: session.workspacePath,
                agentType: session.agentType,
                connectionState: session.connectionState,
                isProcessing: session.isProcessing,
                onStart: { Task { try? await processManager.start(session) } },
                onStop: { Task { await processManager.stop(session) } }
            )
            
            Divider()
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(session.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                        
                        // Reasoning indicator
                        if !session.reasoningText.isEmpty {
                            ReasoningView(text: session.reasoningText)
                        }
                        
                        // Processing indicator
                        if session.isProcessing && session.reasoningText.isEmpty {
                            ProcessingIndicator()
                        }
                    }
                    .padding()
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: session.messages.count) { _, _ in
                    scrollToBottom()
                }
                .onChange(of: session.reasoningText) { _, _ in
                    scrollToBottom()
                }
            }
            
            // Error banner
            if let error = session.error {
                ErrorBanner(message: error.message) {
                    session.dismissError()
                }
            }
            
            // Approval request
            if let approval = session.pendingApproval {
                ApprovalBanner(
                    request: approval,
                    onApprove: { Task { await session.approve() } },
                    onReject: { Task { await session.reject() } }
                )
            }
            
            Divider()
            
            // Composer
            ComposerView(
                isEnabled: session.connectionState.isConnected && !session.isProcessing,
                onSend: { content in
                    Task { await session.send(content) }
                }
            )
        }
        .background(Color.editorBackground)
    }
    
    // MARK: - Helpers
    
    private func scrollToBottom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if let lastMessage = session.messages.last {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Header

struct ConversationHeaderView: View {
    let workspacePath: String
    let agentType: AgentType
    let connectionState: ProcessState
    let isProcessing: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        HStack {
            // Agent info
            HStack(spacing: 8) {
                Image(systemName: agentType.icon)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(agentType.displayName)
                        .font(.headline)
                    
                    Text(workspacePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if connectionState.isConnected {
                    Button("Stop", action: onStop)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if case .connecting = connectionState {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Start", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding()
    }
    
    private var statusColor: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Reasoning View

struct ReasoningView: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain")
                .foregroundStyle(.purple)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            
            Spacer()
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            
            Text("Agent is processing...")
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.callout)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - Approval Banner

struct ApprovalBanner: View {
    let request: ApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                
                Text("Approval Required")
                    .font(.headline)
                
                Spacer()
            }
            
            Text(request.description)
                .font(.body)
            
            HStack {
                Button("Reject", action: onReject)
                    .buttonStyle(.bordered)
                
                Button("Approve", action: onApprove)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Preview

#Preview {
    Text("ConversationView Preview")
}
