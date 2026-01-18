//
//  ComposerView.swift
//  devys
//
//  Text input for composing messages to the agent.
//

import SwiftUI

struct ComposerView: View {
    let isEnabled: Bool
    let onSend: (String) -> Void
    
    @State private var text = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Text editor
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 40, maxHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($isFocused)
                .disabled(!isEnabled)
                .onSubmit(sendIfValid)
            
            // Send button
            Button(action: sendIfValid) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
        .background(Color.sidebarBackground)
    }
    
    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func sendIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && isEnabled else { return }
        
        onSend(trimmed)
        text = ""
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        ComposerView(isEnabled: true) { message in
            print("Sent: \(message)")
        }
    }
}
