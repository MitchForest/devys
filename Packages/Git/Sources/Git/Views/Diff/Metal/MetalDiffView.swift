// MetalDiffView.swift
// SwiftUI wrapper with layout + optional hunk actions.

import SwiftUI
import Syntax
import Rendering
import UI

@MainActor
struct MetalDiffView: View {
    let diffSnapshotInput: DiffSnapshot
    let filePath: String
    let mode: DiffViewMode
    let configuration: DiffRenderConfiguration
    let isStaged: Bool
    let focusedHunkIndex: Int?
    let onAcceptHunk: ((Int) async -> Void)?
    let onRejectHunk: ((Int) async -> Void)?

    @State private var layout: DiffRenderLayout = .unified(
        .init(
            rows: [],
            hunkHeaders: [],
            contentSize: .zero,
            maxLineNumberDigits: 1,
            sourceDocuments: .empty
        )
    )
    @State private var diffSnapshot: DiffSnapshot = .empty
    @State private var scrollOffset: CGPoint = .zero
    @State private var availableWidth: CGFloat = 0
    @State private var diffTheme: DiffTheme = .current()
    @State private var themeName: String = "devys-dark"
    @State private var largeContentPolicy: DiffLargeContentPolicy = .init(totalLines: 0)
    @State private var layoutTask: Task<Void, Never>?
    @State private var layoutGeneration: Int = 0
    @State private var bannerDismissed = false
    @State private var splitRatio: CGFloat = 0.5

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.devysTheme) private var devysTheme

    init(
        diff: ParsedDiff,
        filePath: String,
        mode: DiffViewMode,
        configuration: DiffRenderConfiguration,
        isStaged: Bool,
        focusedHunkIndex: Int? = nil,
        onAcceptHunk: ((Int) async -> Void)? = nil,
        onRejectHunk: ((Int) async -> Void)? = nil
    ) {
        self.diffSnapshotInput = DiffSnapshot(from: diff)
        self.filePath = filePath
        self.mode = mode
        self.configuration = configuration
        self.isStaged = isStaged
        self.focusedHunkIndex = focusedHunkIndex
        self.onAcceptHunk = onAcceptHunk
        self.onRejectHunk = onRejectHunk
    }

    init(
        snapshot: DiffSnapshot,
        filePath: String,
        mode: DiffViewMode,
        configuration: DiffRenderConfiguration,
        isStaged: Bool,
        focusedHunkIndex: Int? = nil,
        onAcceptHunk: ((Int) async -> Void)? = nil,
        onRejectHunk: ((Int) async -> Void)? = nil
    ) {
        self.diffSnapshotInput = snapshot
        self.filePath = filePath
        self.mode = mode
        self.configuration = configuration
        self.isStaged = isStaged
        self.focusedHunkIndex = focusedHunkIndex
        self.onAcceptHunk = onAcceptHunk
        self.onRejectHunk = onRejectHunk
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                MetalDiffViewRepresentable(
                    layout: layout,
                    theme: diffTheme,
                    themeName: themeName,
                    language: LanguageDetector.detect(from: filePath),
                    configuration: effectiveConfiguration,
                    syntaxHighlightingEnabled: effectiveSyntaxHighlightingEnabled,
                    maxHighlightLineLength: largeContentPolicy.maximumSyntaxLineLength,
                    syntaxBacklogPolicy: largeContentPolicy.syntaxBacklogPolicy,
                    scrollOffset: $scrollOffset,
                    splitRatio: $splitRatio
                )

                if let onAcceptHunk, let onRejectHunk {
                    hunkActionsOverlay(width: width, onAcceptHunk: onAcceptHunk, onRejectHunk: onRejectHunk)
                }

                if shouldShowPerformanceBanner {
                    performanceBanner
                        .padding(12)
                }
            }
            .clipped()
            .onAppear {
                updateTheme()
                updateLargeContentPolicy()
                refreshDiffSnapshot()
                rebuildLayout(width: width)
            }
            .onChange(of: width) { _, newWidth in
                rebuildLayout(width: newWidth)
            }
            .onChange(of: diffSnapshotInput) { _, _ in
                updateLargeContentPolicy()
                bannerDismissed = false
                refreshDiffSnapshot()
                rebuildLayout(width: width)
            }
            .onChange(of: mode) { _, _ in
                rebuildLayout(width: width)
            }
            .onChange(of: configuration) { _, _ in
                rebuildLayout(width: width)
            }
            .onChange(of: colorScheme) { _, _ in
                updateTheme()
            }
            .onChange(of: splitRatio) { _, _ in
                rebuildLayout(width: width)
            }
        }
    }

    private func updateTheme() {
        let requestedThemeName = devysTheme.isDark ? "devys-dark" : "devys-light"
        let resolved = ThemeRegistry.resolvedTheme(name: requestedThemeName)
        diffTheme = DiffTheme(theme: resolved.theme)
        themeName = resolved.descriptor.name
    }

    private func rebuildLayout(width: CGFloat) {
        guard width > 0 else { return }
        availableWidth = width
        let metrics = EditorMetrics.measure(fontSize: configuration.fontSize, fontName: configuration.fontName)
        let configSnapshot = effectiveConfiguration
        let diffSnapshot = diffSnapshot
        let modeSnapshot = mode
        let lineHeight = metrics.lineHeight
        let cellWidth = metrics.cellWidth
        let ratioSnapshot = splitRatio
        let generation = layoutGeneration + 1
        layoutGeneration = generation

        layoutTask?.cancel()
        layoutTask = Task { @MainActor in
            let buildTask = Task.detached(priority: .userInitiated) {
                DiffRenderLayoutBuilder.build(
                    snapshot: diffSnapshot,
                    mode: modeSnapshot,
                    configuration: configSnapshot,
                    lineHeight: lineHeight,
                    cellWidth: cellWidth,
                    availableWidth: width,
                    splitRatio: ratioSnapshot
                )
            }
            let layout = await buildTask.value
            guard layoutGeneration == generation else { return }
            self.layout = layout
            self.layoutTask = nil
        }
    }

    private func refreshDiffSnapshot() {
        diffSnapshot = diffSnapshotInput
    }

    private func updateLargeContentPolicy() {
        largeContentPolicy = DiffLargeContentPolicy(snapshot: diffSnapshotInput)
    }

    private var effectiveConfiguration: DiffRenderConfiguration {
        var config = configuration
        if !largeContentPolicy.enableWordDiff {
            config.showWordDiff = false
        }
        if !largeContentPolicy.enableWrap {
            config.wrapLines = false
        }
        return config
    }

    private var effectiveSyntaxHighlightingEnabled: Bool {
        diffSnapshotInput.sourceDocuments.supportsSyntaxHighlighting
            && largeContentPolicy.enableSyntaxHighlighting
    }

    private var shouldShowPerformanceBanner: Bool {
        largeContentPolicy.isReduced && !bannerDismissed
    }

    private var performanceBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(devysTheme.visibleAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Large diff (\(largeContentPolicy.totalLines) lines)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(devysTheme.text)
                Text(largeContentPolicy.bannerDetailText)
                    .font(.system(size: 11))
                    .foregroundStyle(devysTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Button("Dismiss") {
                bannerDismissed = true
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(devysTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(devysTheme.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(devysTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 420, alignment: .leading)
    }

    @ViewBuilder
    private func hunkActionsOverlay(
        width: CGFloat,
        onAcceptHunk: @escaping (Int) async -> Void,
        onRejectHunk: @escaping (Int) async -> Void
    ) -> some View {
        let metrics = EditorMetrics.measure(fontSize: configuration.fontSize, fontName: configuration.fontName)
        ForEach(layout.hunkHeaders) { header in
            let y = CGFloat(header.rowIndex) * metrics.lineHeight - scrollOffset.y
            if header.hunkIndex < diffSnapshotInput.hunks.count {
                HunkActionBar(
                    hunk: diffSnapshotInput.hunks[header.hunkIndex],
                    isStaged: isStaged,
                    isFocused: focusedHunkIndex == header.hunkIndex,
                    onAccept: { await onAcceptHunk(header.hunkIndex) },
                    onReject: { await onRejectHunk(header.hunkIndex) }
                )
                .frame(width: width)
                .offset(x: -scrollOffset.x, y: y)
            }
        }
    }
}
