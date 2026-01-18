//
//  MessageView.swift
//  devys
//
//  Renders a single message with markdown, code blocks, tool calls, and diffs.
//

import SwiftUI

struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            MessageAvatar(role: message.role)
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Role label
                HStack {
                    Text(message.role.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                // Message content with markdown
                MessageContentView(content: message.content)
                
                // Tool calls
                if !message.toolCalls.isEmpty {
                    ToolCallsView(toolCalls: message.toolCalls)
                }
                
                // Diffs
                if !message.diffs.isEmpty {
                    DiffsView(diffs: message.diffs)
                }
            }
        }
        .padding()
        .background(message.role == .user ? Color.clear : Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Avatar

struct MessageAvatar: View {
    let role: MessageRole
    
    var body: some View {
        ZStack {
            Circle()
                .fill(role == .user ? Color.blue : Color.purple)
                .frame(width: 32, height: 32)
            
            Image(systemName: role.icon)
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Message Content

struct MessageContentView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseContent(content), id: \.id) { block in
                switch block.type {
                case .text:
                    Text(LocalizedStringKey(block.content))
                        .font(.body)
                        .textSelection(.enabled)
                    
                case .code(let language):
                    CodeBlockView(code: block.content, language: language)
                }
            }
        }
    }
    
    private func parseContent(_ content: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""
        
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(ContentBlock(type: .code(language: codeLanguage), content: codeContent.trimmingCharacters(in: .newlines)))
                    codeContent = ""
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    if !currentText.isEmpty {
                        blocks.append(ContentBlock(type: .text, content: currentText.trimmingCharacters(in: .newlines)))
                        currentText = ""
                    }
                    codeLanguage = String(line.dropFirst(3))
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeContent += line + "\n"
            } else {
                currentText += line + "\n"
            }
        }
        
        if inCodeBlock && !codeContent.isEmpty {
            blocks.append(ContentBlock(type: .code(language: codeLanguage), content: codeContent.trimmingCharacters(in: .newlines)))
        } else if !currentText.isEmpty {
            blocks.append(ContentBlock(type: .text, content: currentText.trimmingCharacters(in: .newlines)))
        }
        
        return blocks
    }
}

// MARK: - Content Block

struct ContentBlock: Identifiable {
    let id = UUID()
    let type: ContentBlockType
    let content: String
}

enum ContentBlockType {
    case text
    case code(language: String)
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String
    
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.8))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Tool Calls View

struct ToolCallsView: View {
    let toolCalls: [ToolCall]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(toolCalls) { call in
                ToolCallRow(toolCall: call)
            }
        }
    }
}

struct ToolCallRow: View {
    let toolCall: ToolCall
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: toolCall.status.icon)
                        .foregroundStyle(colorForStatus)
                    
                    Text(toolCall.displayDescription)
                        .font(.caption.monospaced())
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Arguments:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(formatArguments(toolCall.arguments))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    if let result = toolCall.result {
                        Text("Result:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(result)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .lineLimit(10)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var colorForStatus: Color {
        switch toolCall.status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private func formatArguments(_ args: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: .prettyPrinted),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - Diffs View

struct DiffsView: View {
    let diffs: [FileDiff]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(diffs) { diff in
                DiffRow(diff: diff)
            }
        }
    }
}

struct DiffRow: View {
    let diff: FileDiff
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: diff.icon)
                        .foregroundStyle(.secondary)
                    
                    Text(diff.path)
                        .font(.caption.monospaced())
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(diff.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            
            if isExpanded && !diff.content.isEmpty {
                ScrollView {
                    Text(diff.content)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .background(Color.gray.opacity(0.05))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    let message = Message(
        role: .assistant,
        content: "Here's a Swift example:\n\n```swift\nfunc hello() {\n    print(\"Hello, World!\")\n}\n```\n\nThis function prints a greeting."
    )
    MessageView(message: message)
        .padding()
}
