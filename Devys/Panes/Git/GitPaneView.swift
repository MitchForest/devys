import SwiftUI

/// Git pane showing repository status, staged/unstaged changes, and commit controls.
public struct GitPaneView: View {
    let paneId: UUID
    @State private var gitState: GitState

    // Canvas state for diff pane linking
    @Environment(\.canvasState) private var _canvas

    // Discard confirmation
    @State private var showDiscardConfirmation = false
    @State private var changeToDiscard: GitFileChange?

    public init(paneId: UUID, repositoryURL: URL?) {
        self.paneId = paneId
        self._gitState = State(initialValue: GitState(repositoryURL: repositoryURL))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Repository header
            if let info = gitState.repositoryInfo {
                repositoryHeader(info)
            }

            Divider()

            if gitState.repositoryURL == nil {
                emptyState
            } else if gitState.isLoading && !gitState.hasChanges {
                loadingState
            } else {
                changesContent
            }
        }
        .task {
            await gitState.refresh()
        }
        .alert("Discard Changes?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) {
                changeToDiscard = nil
            }
            Button("Discard", role: .destructive) {
                if let change = changeToDiscard {
                    Task { await gitState.discard(change) }
                }
                changeToDiscard = nil
            }
        } message: {
            if let change = changeToDiscard {
                Text("This will permanently discard all changes to \"\(change.fileName)\". This cannot be undone.")
            }
        }
        // Listen for hunk action notifications
        .onReceive(NotificationCenter.default.publisher(for: .stageHunk)) { notification in
            handleHunkAction(notification, action: .stage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .unstageHunk)) { notification in
            handleHunkAction(notification, action: .unstage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .discardHunk)) { notification in
            handleHunkAction(notification, action: .discard)
        }
    }

    // MARK: - Hunk Action Handling

    private enum HunkAction {
        case stage, unstage, discard
    }

    private func handleHunkAction(_ notification: Notification, action: HunkAction) {
        guard let request = notification.object as? HunkActionRequest else { return }

        Task {
            switch action {
            case .stage:
                await gitState.stageHunk(request.hunk, filePath: request.filePath)
            case .unstage:
                await gitState.unstageHunk(request.hunk, filePath: request.filePath)
            case .discard:
                await gitState.discardHunk(request.hunk, filePath: request.filePath)
            }

            // Refresh the diff pane
            if let change = gitState.selectedChange, let canvas = _canvas {
                if let diffPaneId = findLinkedDiffPane() {
                    if let diff = gitState.selectedDiff {
                        canvas.updateDiffPane(
                            diffPaneId,
                            filePath: change.path,
                            rawDiff: diff,
                            isStaged: change.isStaged
                        )
                    }
                }
            }
        }
    }

    private func findLinkedDiffPane() -> UUID? {
        guard let canvas = _canvas,
              let paneIndex = canvas.paneIndex(withId: paneId),
              case .git(let gitState) = canvas.panes[paneIndex].type else {
            return nil
        }
        return gitState.linkedDiffPaneId
    }

    // MARK: - Repository Header

    private func repositoryHeader(_ info: GitRepositoryInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(info.currentBranch ?? "detached")
                .font(.system(size: 12, weight: .medium))

            if info.aheadCount > 0 {
                Label("\(info.aheadCount)", systemImage: "arrow.up")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }

            if info.behindCount > 0 {
                Label("\(info.behindCount)", systemImage: "arrow.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button {
                Task { await gitState.refresh() }
            } label: {
                Image(systemName: gitState.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .font(.system(size: 11))
                    .rotationEffect(gitState.isLoading ? .degrees(360) : .zero)
                    .animation(gitState.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: gitState.isLoading)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Changes Content

    private var changesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Staged changes section
                if !gitState.stagedChanges.isEmpty {
                    changesSection(
                        title: "Staged Changes",
                        changes: gitState.stagedChanges,
                        isStaged: true
                    )
                }

                // Unstaged changes section
                if !gitState.unstagedChanges.isEmpty {
                    changesSection(
                        title: "Changes",
                        changes: gitState.unstagedChanges,
                        isStaged: false
                    )
                }

                // No changes message
                if !gitState.hasChanges && !gitState.isLoading {
                    noChangesView
                }

                // Commit section
                if !gitState.stagedChanges.isEmpty {
                    commitSection
                }

                // Recent commits
                if !gitState.recentCommits.isEmpty {
                    recentCommitsSection
                }
            }
            .padding(12)
        }
    }

    // MARK: - Changes Section

    private func changesSection(title: String, changes: [GitFileChange], isStaged: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("(\(changes.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer()

                if isStaged {
                    Button("Unstage All") {
                        Task { await gitState.unstageAll() }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                } else {
                    Button("Stage All") {
                        Task { await gitState.stageAll() }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }

            ForEach(changes) { change in
                GitChangeRow(
                    change: change,
                    onStage: {
                        Task { await gitState.stage(change) }
                    },
                    onUnstage: {
                        Task { await gitState.unstage(change) }
                    },
                    onDiscard: {
                        changeToDiscard = change
                        showDiscardConfirmation = true
                    },
                    onSelect: {
                        openDiffForChange(change)
                    }
                )
            }
        }
    }

    // MARK: - Commit Section

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit Message")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $gitState.commitMessage)
                .font(.system(size: 12))
                .frame(minHeight: 60, maxHeight: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()

                Button {
                    Task { await gitState.commit() }
                } label: {
                    Text("Commit")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(gitState.canCommit ? Color.blue : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!gitState.canCommit)
            }
        }
    }

    // MARK: - Recent Commits Section

    private var recentCommitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Commits")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(gitState.recentCommits) { commit in
                HStack(spacing: 8) {
                    Text(commit.shortHash)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(commit.message)
                        .font(.system(size: 11))
                        .lineLimit(1)

                    Spacer()

                    Text(commit.relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No Repository")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Open a project to view git status")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noChangesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.green)

            Text("No Changes")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Working tree clean")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Diff Opening

    /// Open a diff for a change in the linked diff pane
    private func openDiffForChange(_ change: GitFileChange) {
        guard let canvas = _canvas else {
            // Fallback: just load diff internally
            Task { await gitState.loadDiff(for: change) }
            return
        }

        // Find or create linked diff pane
        guard let diffPaneId = canvas.findOrCreateLinkedDiff(for: paneId) else {
            return
        }

        // Load the diff and update the diff pane
        Task {
            await gitState.loadDiff(for: change)
            if let diff = gitState.selectedDiff {
                canvas.updateDiffPane(
                    diffPaneId,
                    filePath: change.path,
                    rawDiff: diff,
                    isStaged: change.isStaged
                )
            }
        }
    }
}

// MARK: - Git Change Row

/// Row for displaying a single file change
struct GitChangeRow: View {
    let change: GitFileChange
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: change.status.iconName)
                .font(.system(size: 10))
                .foregroundStyle(statusColor)
                .frame(width: 16)

            // File name
            VStack(alignment: .leading, spacing: 2) {
                Text(change.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)

                if change.directory != "." && !change.directory.isEmpty {
                    Text(change.directory)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action buttons (shown on hover)
            if isHovered {
                HStack(spacing: 4) {
                    // Discard button (only for unstaged changes)
                    if !change.isStaged {
                        Button(action: onDiscard) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Discard changes")
                    }

                    // Stage/Unstage button
                    Button {
                        if change.isStaged {
                            onUnstage()
                        } else {
                            onStage()
                        }
                    } label: {
                        Image(systemName: change.isStaged ? "minus" : "plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(change.isStaged ? "Unstage" : "Stage")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(perform: onSelect)
    }

    private var statusColor: Color {
        switch change.status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed, .copied: return .blue
        case .untracked: return .gray
        case .ignored: return .gray
        case .unmerged: return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    GitPaneView(
        paneId: UUID(),
        repositoryURL: URL(fileURLWithPath: "/Users/mitchwhite/Code/devys")
    )
    .frame(width: 300, height: 500)
}
