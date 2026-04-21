import SwiftUI
import UI

@MainActor
public struct GitDiffDocumentView: View {
    let filePath: String
    let diffText: String?
    let isLoading: Bool
    let errorMessage: String?
    let isStaged: Bool
    @Binding var ignoreWhitespace: Bool
    let statusMessage: String?
    let onExpandContext: () -> Void
    let onShowAllContext: () -> Void
    let onStagePatch: ((String) -> Void)?
    let onDiscardPatch: ((String, Bool) -> Void)?

    @State private var diffViewMode: DiffViewMode = .unified
    @State private var showWordDiff = true
    @State private var showLineNumbers = true
    @State private var wrapLines = false
    @State private var changeStyle: DiffChangeStyle = .fullBackground
    @State private var focusedHunkIndex: Int?

    public init(
        filePath: String,
        diffText: String?,
        isLoading: Bool,
        errorMessage: String?,
        isStaged: Bool,
        ignoreWhitespace: Binding<Bool>,
        statusMessage: String? = nil,
        onExpandContext: @escaping () -> Void,
        onShowAllContext: @escaping () -> Void,
        onStagePatch: ((String) -> Void)? = nil,
        onDiscardPatch: ((String, Bool) -> Void)? = nil
    ) {
        self.filePath = filePath
        self.diffText = diffText
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.isStaged = isStaged
        self._ignoreWhitespace = ignoreWhitespace
        self.statusMessage = statusMessage
        self.onExpandContext = onExpandContext
        self.onShowAllContext = onShowAllContext
        self.onStagePatch = onStagePatch
        self.onDiscardPatch = onDiscardPatch
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbarView
            Divider()

            if let errorMessage,
               !errorMessage.isEmpty {
                errorBanner(errorMessage)
            }

            if let statusMessage,
               !statusMessage.isEmpty {
                statusBanner(statusMessage)
            }

            if let diff = parsedDiff {
                if diff.isBinary {
                    binaryFileView
                } else if !diff.hasChanges {
                    noChangesView
                } else {
                    diffContentView(diff: diff)
                }
            } else if isLoading {
                loadingView
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: diffText) { _, _ in
            focusedHunkIndex = nil
        }
        .onKeyPress(.downArrow) {
            nextHunk()
            return .handled
        }
        .onKeyPress(.upArrow) {
            previousHunk()
            return .handled
        }
        .onKeyPress(KeyEquivalent("j")) {
            nextHunk()
            return .handled
        }
        .onKeyPress(KeyEquivalent("k")) {
            previousHunk()
            return .handled
        }
        .onKeyPress(KeyEquivalent("a")) {
            stageFocusedHunk()
            return .handled
        }
        .onKeyPress(KeyEquivalent("r")) {
            discardFocusedHunk()
            return .handled
        }
    }

    private var parsedDiff: DiffSnapshot? {
        guard let diffText else { return nil }
        return DiffSnapshot(from: DiffParser.parse(diffText))
    }

    private var toolbarView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(filePath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let diff = parsedDiff, diff.hasChanges {
                HStack(spacing: 8) {
                    Text("+\(diff.totalAdded)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DevysColors.success)

                    Text("-\(diff.totalRemoved)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DevysColors.error)
                }
            }

            Divider()
                .frame(height: 16)

            Picker("View Mode", selection: $diffViewMode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 100)

            Menu {
                Toggle("Word Diff", isOn: $showWordDiff)
                Toggle("Line Numbers", isOn: $showLineNumbers)
                Toggle("Wrap Lines", isOn: $wrapLines)
                Toggle("Ignore Whitespace", isOn: $ignoreWhitespace)

                Picker("Change Style", selection: $changeStyle) {
                    ForEach(DiffChangeStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }

                Divider()

                Button("Expand Context", action: onExpandContext)
                Button("Show All Context", action: onShowAllContext)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func diffContentView(diff: DiffSnapshot) -> some View {
        MetalDiffView(
            snapshot: diff,
            filePath: filePath,
            mode: diffViewMode,
            configuration: DiffRenderConfiguration(
                fontName: "Menlo",
                fontSize: 12,
                showLineNumbers: showLineNumbers,
                showPrefix: true,
                showWordDiff: showWordDiff,
                wrapLines: wrapLines,
                changeStyle: changeStyle,
                showsHunkHeaders: false
            ),
            isStaged: isStaged,
            focusedHunkIndex: focusedHunkIndex,
            onAcceptHunk: { index in
                guard let patch = patch(for: index, in: diff) else { return }
                onStagePatch?(patch)
            },
            onRejectHunk: { index in
                guard let patch = patch(for: index, in: diff) else { return }
                onDiscardPatch?(patch, isStaged)
            }
        )
    }

    private func patch(for index: Int, in diff: DiffSnapshot) -> String? {
        guard diff.hunks.indices.contains(index) else { return nil }
        return diff.hunks[index].toPatch(oldPath: filePath, newPath: filePath)
    }

    private func nextHunk() {
        guard let diff = parsedDiff, !diff.hunks.isEmpty else { return }
        let current = focusedHunkIndex ?? -1
        focusedHunkIndex = min(current + 1, diff.hunks.count - 1)
    }

    private func previousHunk() {
        guard let diff = parsedDiff, !diff.hunks.isEmpty else { return }
        let current = focusedHunkIndex ?? diff.hunks.count
        focusedHunkIndex = max(current - 1, 0)
    }

    private func stageFocusedHunk() {
        guard let diff = parsedDiff,
              let focusedHunkIndex,
              let patch = patch(for: focusedHunkIndex, in: diff) else {
            return
        }
        onStagePatch?(patch)
    }

    private func discardFocusedHunk() {
        guard let diff = parsedDiff,
              let focusedHunkIndex,
              let patch = patch(for: focusedHunkIndex, in: diff) else {
            return
        }
        onDiscardPatch?(patch, isStaged)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundStyle(DevysColors.error)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading diff...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Select a File")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Choose a file from the sidebar to view its diff.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var binaryFileView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Binary File")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("This file is binary and cannot be displayed as a diff.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noChangesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(DevysColors.success.opacity(0.6))

            Text("No Changes")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("This file has no changes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
