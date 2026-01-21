import SwiftUI

// MARK: - Diff Pane State

/// State for a diff pane
public struct DiffPaneState: Equatable, Hashable {
    /// The file path being diffed
    public var filePath: String?

    /// Raw diff text
    public var rawDiff: String

    /// Whether this is a staged diff
    public var isStaged: Bool

    public init(filePath: String? = nil, rawDiff: String = "", isStaged: Bool = false) {
        self.filePath = filePath
        self.rawDiff = rawDiff
        self.isStaged = isStaged
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(filePath)
        hasher.combine(isStaged)
    }
}

// MARK: - Diff Pane View

/// View for displaying file diffs with syntax coloring
public struct DiffPaneView: View {
    let paneId: UUID
    let state: DiffPaneState

    @State private var parsedDiff: ParsedDiff?

    // Discard confirmation
    @State private var showDiscardConfirmation = false
    @State private var hunkToDiscard: DiffHunk?

    public init(paneId: UUID, state: DiffPaneState) {
        self.paneId = paneId
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            diffHeader

            Divider()

            // Content
            if let diff = parsedDiff {
                if diff.isBinary {
                    binaryFileView
                } else if diff.hunks.isEmpty {
                    emptyDiffView
                } else {
                    diffContent(diff)
                }
            } else {
                emptyStateView
            }
        }
        .onAppear {
            parseDiff()
        }
        .onChange(of: state.rawDiff) { _, _ in
            parseDiff()
        }
        .alert("Discard Hunk?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) {
                hunkToDiscard = nil
            }
            Button("Discard", role: .destructive) {
                if let hunk = hunkToDiscard, let filePath = state.filePath {
                    postHunkAction(.discardHunk, hunk: hunk, filePath: filePath)
                }
                hunkToDiscard = nil
            }
        } message: {
            Text("This will permanently discard this change. This cannot be undone.")
        }
    }

    private func parseDiff() {
        parsedDiff = DiffParser.parse(state.rawDiff)
    }

    // MARK: - Header

    private var diffHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let path = state.filePath {
                Text(path)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            } else {
                Text("Diff")
                    .font(.system(size: 12, weight: .medium))
            }

            if state.isStaged {
                Text("(staged)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let diff = parsedDiff {
                HStack(spacing: 8) {
                    Text("+\(diff.totalAdded)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green)

                    Text("-\(diff.totalRemoved)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Diff Content

    private func diffContent(_ diff: ParsedDiff) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.hunks) { hunk in
                    HunkView(
                        hunk: hunk,
                        isStaged: state.isStaged,
                        onStage: {
                            if let filePath = state.filePath {
                                postHunkAction(.stageHunk, hunk: hunk, filePath: filePath)
                            }
                        },
                        onUnstage: {
                            if let filePath = state.filePath {
                                postHunkAction(.unstageHunk, hunk: hunk, filePath: filePath)
                            }
                        },
                        onDiscard: {
                            hunkToDiscard = hunk
                            showDiscardConfirmation = true
                        }
                    )
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No Diff Selected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Click a file in the Git pane to view its diff")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDiffView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text("No Changes")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var binaryFileView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Binary File")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Cannot display diff for binary files")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hunk Actions

    private func postHunkAction(_ action: Notification.Name, hunk: DiffHunk, filePath: String) {
        let request = HunkActionRequest(hunk: hunk, filePath: filePath, isStaged: state.isStaged)
        NotificationCenter.default.post(name: action, object: request)
    }
}

// MARK: - Hunk Action Request

/// Request to perform an action on a single hunk
public struct HunkActionRequest {
    public let hunk: DiffHunk
    public let filePath: String
    public let isStaged: Bool
}

public extension Notification.Name {
    /// Request to stage a hunk
    static let stageHunk = Notification.Name("devys.stageHunk")

    /// Request to unstage a hunk
    static let unstageHunk = Notification.Name("devys.unstageHunk")

    /// Request to discard a hunk
    static let discardHunk = Notification.Name("devys.discardHunk")
}

// MARK: - Hunk View

/// View for a single diff hunk
struct HunkView: View {
    let hunk: DiffHunk
    let isStaged: Bool
    let onStage: (() -> Void)?
    let onUnstage: (() -> Void)?
    let onDiscard: (() -> Void)?

    @State private var isCollapsed = false
    @State private var isHovered = false

    init(
        hunk: DiffHunk,
        isStaged: Bool = false,
        onStage: (() -> Void)? = nil,
        onUnstage: (() -> Void)? = nil,
        onDiscard: (() -> Void)? = nil
    ) {
        self.hunk = hunk
        self.isStaged = isStaged
        self.onStage = onStage
        self.onUnstage = onUnstage
        self.onDiscard = onDiscard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header with actions
            HStack(spacing: 0) {
                // Collapse/expand button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text(hunk.header)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("+\(hunk.addedCount) -\(hunk.removedCount)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                // Action buttons (shown on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        if isStaged {
                            // Unstage hunk button
                            if let onUnstage = onUnstage {
                                Button(action: onUnstage) {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                }
                                .buttonStyle(.plain)
                                .help("Unstage this hunk")
                            }
                        } else {
                            // Discard hunk button
                            if let onDiscard = onDiscard {
                                Button(action: onDiscard) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Discard this hunk")
                            }

                            // Stage hunk button
                            if let onStage = onStage {
                                Button(action: onStage) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                .help("Stage this hunk")
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .onHover { hovering in
                isHovered = hovering
            }

            // Hunk lines
            if !isCollapsed {
                ForEach(hunk.lines.filter { $0.type != .header }) { line in
                    DiffLineView(line: line)
                }
            }
        }
    }
}

// MARK: - Diff Line View

/// View for a single diff line
struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            HStack(spacing: 0) {
                // Old line number
                Text(line.oldLineNumber.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)

                // New line number
                Text(line.newLineNumber.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.trailing, 8)

            // Line indicator
            Text(lineIndicator)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(indicatorColor)
                .frame(width: 12)

            // Content
            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(contentColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var lineIndicator: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        case .header: return ""
        }
    }

    private var indicatorColor: Color {
        switch line.type {
        case .added: return .green
        case .removed: return .red
        case .context, .header: return .secondary
        }
    }

    private var contentColor: Color {
        switch line.type {
        case .added: return .primary
        case .removed: return .primary
        case .context, .header: return .primary
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .context, .header: return .clear
        }
    }
}

// MARK: - Preview

#Preview("With Diff") {
    let sampleDiff = """
    --- a/test.swift
    +++ b/test.swift
    @@ -1,5 +1,6 @@
     import Foundation

    +let greeting = "Hello"
     struct Test {
    -    let value: Int
    +    let value: String
     }
    """

    return DiffPaneView(
        paneId: UUID(),
        state: DiffPaneState(filePath: "test.swift", rawDiff: sampleDiff)
    )
    .frame(width: 500, height: 400)
}

#Preview("Empty") {
    DiffPaneView(
        paneId: UUID(),
        state: DiffPaneState()
    )
    .frame(width: 500, height: 400)
}
