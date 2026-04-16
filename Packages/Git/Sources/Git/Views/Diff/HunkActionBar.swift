// HunkActionBar.swift
// Stage/Unstage/Discard action bar for individual hunks.
//
// - Stage: Stage this hunk (for unstaged changes)
// - Unstage: Unstage this hunk (for staged changes)
// - Discard: Discard the changes entirely (revert to HEAD)

import SwiftUI
import UI

/// Action bar for staging/unstaging/discarding individual hunks.
/// Displays above each hunk with Stage/Unstage and Discard buttons.
@MainActor
struct HunkActionBar: View {
    let hunk: DiffHunk
    let isStaged: Bool
    let isFocused: Bool
    let onAccept: () async -> Void
    let onReject: () async -> Void
    
    @State private var isProcessing = false
    @State private var isHovered = false
    
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
                    .foregroundStyle(DevysColors.success)
                Text("-\(hunk.removedCount)")
                    .foregroundStyle(DevysColors.error)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            
            // Action buttons (always visible, more prominent on hover/focus)
            HStack(spacing: 4) {
                if isStaged {
                    // Unstage button for staged hunks
                    Button {
                        Task {
                            isProcessing = true
                            await onReject()
                            isProcessing = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            if isHovered || isFocused {
                                Text("Unstage")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .padding(.horizontal, isHovered || isFocused ? 8 : 6)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .background(unstageButtonBackground)
                    .foregroundStyle(DevysColors.warning)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                    .disabled(isProcessing)
                    .help("Unstage this hunk")
                } else {
                    // Stage button for unstaged hunks
                    Button {
                        Task {
                            isProcessing = true
                            await onAccept()
                            isProcessing = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            if isHovered || isFocused {
                                Text("Stage")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .padding(.horizontal, isHovered || isFocused ? 8 : 6)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .background(stageButtonBackground)
                    .foregroundStyle(DevysColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                    .disabled(isProcessing)
                    .help("Stage this hunk")

                    // Discard button for unstaged hunks
                    Button {
                        Task {
                            isProcessing = true
                            await onReject()
                            isProcessing = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            if isHovered || isFocused {
                                Text("Discard")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .padding(.horizontal, isHovered || isFocused ? 8 : 6)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .background(discardButtonBackground)
                    .foregroundStyle(DevysColors.error)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                    .disabled(isProcessing)
                    .help("Discard this hunk")
                }
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
        devysTheme.overlay
    }
    
    private var stageButtonBackground: Color {
        DevysColors.success.opacity(isHovered ? 0.25 : 0.15)
    }

    private var unstageButtonBackground: Color {
        DevysColors.warning.opacity(isHovered ? 0.25 : 0.15)
    }

    private var discardButtonBackground: Color {
        DevysColors.error.opacity(isHovered ? 0.25 : 0.15)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        HunkActionBar(
            hunk: DiffHunk(
                id: "preview-hunk-1",
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
                id: "preview-hunk-2",
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
