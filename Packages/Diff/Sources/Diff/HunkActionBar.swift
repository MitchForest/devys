// HunkActionBar.swift
// Quiet hunk header with right-click and double-click affordances.
//
// The bar replaces the rendered hunk header line in the diff viewer. It
// shows the @@ header and +/- stats and exposes per-hunk operations
// through a context menu and a double-click toggle, never inline buttons.

import SwiftUI
import UI

/// Per-hunk header with discoverable (but quiet) staging affordances.
///
/// - Right-click → Stage / Unstage / Discard / Copy Header
/// - Double-click → toggle stage / unstage
/// - Left edge stripe indicates staged (`Colors.warning`) vs unstaged
///   (`Colors.success`) state, brightened when the hunk is focused.
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
        HStack(spacing: Spacing.normal) {
            Text(hunk.header)
                .font(Typography.Code.gutter)
                .foregroundStyle(devysTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.normal)

            HStack(spacing: Spacing.tight) {
                if hunk.addedCount > 0 {
                    Text("+\(hunk.addedCount)")
                        .foregroundStyle(Colors.success)
                }
                if hunk.removedCount > 0 {
                    Text("-\(hunk.removedCount)")
                        .foregroundStyle(Colors.error)
                }
            }
            .font(Typography.micro)
        }
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.paneGap)
        .frame(height: DiffChromeMetrics.hunkActionBarHeight)
        .background(headerBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(stripeColor)
                .frame(width: stripeWidth)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            performToggle()
        }
        .contextMenu {
            if isStaged {
                Button("Unstage Hunk") { performToggle() }
                    .disabled(isProcessing)
            } else {
                Button("Stage Hunk") { performToggle() }
                    .disabled(isProcessing)
                Button("Discard Hunk", role: .destructive) {
                    performReject()
                }
                .disabled(isProcessing)
            }
            Divider()
            Button("Copy Header") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hunk.header, forType: .string)
            }
        }
        .help(toggleHelpText)
    }

    // MARK: - Actions

    private func performToggle() {
        guard !isProcessing else { return }
        Task {
            isProcessing = true
            await onAccept()
            isProcessing = false
        }
    }

    private func performReject() {
        guard !isProcessing else { return }
        Task {
            isProcessing = true
            await onReject()
            isProcessing = false
        }
    }

    // MARK: - Styling

    private var headerBackground: Color {
        isHovered ? devysTheme.cardHover : devysTheme.overlay
    }

    private var stripeColor: Color {
        let base = isStaged ? Colors.warning : Colors.success
        let opacity: Double = isFocused ? 1.0 : (isHovered ? 0.85 : 0.55)
        return base.opacity(opacity)
    }

    private var stripeWidth: CGFloat {
        isFocused ? 3 : 2
    }

    private var toggleHelpText: String {
        isStaged
            ? "Double-click to unstage this hunk. Right-click for more."
            : "Double-click to stage this hunk. Right-click for more."
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
            isStaged: true,
            isFocused: true,
            onAccept: {},
            onReject: {}
        )
    }
    .frame(width: 600)
    .padding()
}
#endif
