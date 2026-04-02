// HunkActionBar.swift
// Accept/Reject action bar for individual hunks.
//
// Inspired by Pierre Diffs' diffAcceptRejectHunk() pattern:
// - Accept: Keep the changes (stage for unstaged, no-op for staged)
// - Reject: Discard the changes entirely (revert to HEAD)

import SwiftUI
import UI

/// Action bar for accepting/rejecting individual hunks.
/// Displays above each hunk with Accept (✓) and Reject (✗) buttons.
@MainActor
struct HunkActionBar: View {
    let hunk: DiffHunk
    let isStaged: Bool
    let isFocused: Bool
    let onAccept: () async -> Void
    let onReject: () async -> Void
    
    @State private var isProcessing = false
    @State private var isHovered = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.devysTheme) private var devysTheme
    
    init(
        hunk: DiffHunk,
        isStaged: Bool,
        isFocused: Bool = false,
        onAccept: @escaping () async -> Void,
        onReject: @escaping () async -> Void
    ) {
        self.hunk = hunk
        self.isStaged = isStaged
        self.isFocused = isFocused
        self.onAccept = onAccept
        self.onReject = onReject
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Hunk info
            Text(hunk.header)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            // Stats
            HStack(spacing: 4) {
                Text("+\(hunk.addedCount)")
                    .foregroundStyle(.green)
                Text("-\(hunk.removedCount)")
                    .foregroundStyle(.red)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            
            // Action buttons (always visible, more prominent on hover/focus)
            HStack(spacing: 4) {
                // Accept button
                Button {
                    Task {
                        isProcessing = true
                        await onAccept()
                        isProcessing = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                        if isHovered || isFocused {
                            Text("Accept")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .padding(.horizontal, isHovered || isFocused ? 8 : 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(acceptButtonBackground)
                .foregroundStyle(acceptButtonForeground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .disabled(isProcessing)
                .help(isStaged ? "Already accepted (staged)" : "Accept: Stage this change")
                
                // Reject button
                Button {
                    Task {
                        isProcessing = true
                        await onReject()
                        isProcessing = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                        if isHovered || isFocused {
                            Text("Reject")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .padding(.horizontal, isHovered || isFocused ? 8 : 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(rejectButtonBackground)
                .foregroundStyle(rejectButtonForeground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .disabled(isProcessing)
                .help("Reject: Discard this change")
            }
            .opacity(isHovered || isFocused ? 1.0 : 0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(headerBackground)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(devysTheme.accent)
                    .frame(width: 3)
            }
        }
        .onHover { isHovered = $0 }
    }
    
    // MARK: - Styling
    
    private var headerBackground: Color {
        devysTheme.elevated
    }
    
    private var acceptButtonBackground: Color {
        if isStaged {
            return Color.secondary.opacity(0.1)
        }
        return colorScheme == .dark
            ? Color.green.opacity(isHovered ? 0.3 : 0.2)
            : Color.green.opacity(isHovered ? 0.25 : 0.15)
    }
    
    private var acceptButtonForeground: Color {
        if isStaged {
            return .secondary
        }
        return colorScheme == .dark
            ? Color.green
            : Color.green.opacity(0.9)
    }
    
    private var rejectButtonBackground: Color {
        colorScheme == .dark
            ? Color.red.opacity(isHovered ? 0.3 : 0.2)
            : Color.red.opacity(isHovered ? 0.25 : 0.15)
    }
    
    private var rejectButtonForeground: Color {
        colorScheme == .dark
            ? Color.red
            : Color.red.opacity(0.9)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        HunkActionBar(
            hunk: DiffHunk(
                header: "@@ -10,5 +10,7 @@",
                lines: [],
                oldStart: 10,
                oldCount: 5,
                newStart: 10,
                newCount: 7
            ),
            isStaged: false,
            isFocused: false,
            onAccept: {},
            onReject: {}
        )
        
        HunkActionBar(
            hunk: DiffHunk(
                header: "@@ -20,3 +22,8 @@",
                lines: [],
                oldStart: 20,
                oldCount: 3,
                newStart: 22,
                newCount: 8
            ),
            isStaged: false,
            isFocused: true,
            onAccept: {},
            onReject: {}
        )
    }
    .frame(width: 600)
    .padding()
}
#endif
