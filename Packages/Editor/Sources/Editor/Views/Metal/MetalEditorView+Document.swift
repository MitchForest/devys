// MetalEditorView+Document.swift
// DevysEditor

#if os(macOS)
// periphery:ignore:all - editor render scheduling hooks are exercised through view lifecycle and tests
import Foundation
import MetalKit
import Syntax
import Rendering
import Text

extension MetalEditorView {
    // MARK: - Document

    func displaySnapshot(
        for visibleRange: Range<Int>,
        document: EditorDocument
    ) -> EditorDisplaySnapshot {
        if let snapshot = document.snapshot {
            updateLargeFilePolicy(for: snapshot)
            return displayModel.snapshot(
                EditorDisplaySnapshotRequest(
                    documentReopenIdentity: document.reopenIdentity,
                    documentSnapshot: snapshot,
                    syntaxSnapshot: document.syntaxController?.currentSnapshot(),
                    semanticOverlaySnapshot: semanticOverlaySnapshot,
                    visibleRange: visibleRange,
                    renderContext: displayRenderContext
                )
            )
        }

        let visibleLines = document.lines(in: visibleRange).enumerated().map { offset, line in
            LineSlice(lineIndex: visibleRange.lowerBound + offset, text: line)
        }
        largeFilePolicy = .default
        return displayModel.previewSnapshot(
            EditorPreviewSnapshotRequest(
                documentReopenIdentity: document.reopenIdentity,
                documentVersion: document.documentVersion,
                visibleLines: visibleLines,
                visibleRange: visibleRange,
                renderContext: displayRenderContext
            )
        )
    }

    func documentDidChange() {
        guard let document = document else {
            resetDocumentState()
            return
        }

        displayModel.reset()
        configureLineBuffer(for: document)
        startHighlighting(for: document)
    }

    private func resetDocumentState() {
        lineBuffer = nil
        syntaxSchedulingCoordinator.cancelAll()
        pendingThemeSyntaxController = nil
        pendingThemeDescriptor = nil
        preparedFrame = nil
        appliedThemeDescriptor = ThemeRegistry.preferredThemeDescriptor
        largeFilePolicy = .default
        revisitTrackingIdentifier = nil
        hasRecordedRevisitInteractiveFrame = false
        hasRecordedRevisitHighlightedFrame = false
        shouldRecordScrollTrace = false
        displayModel.reset()
    }

    private func configureLineBuffer(for document: EditorDocument) {
        lineBuffer = LineBuffer(document: document, metrics: metrics)
        lineBuffer?.viewportHeight = bounds.height
    }

    private func startHighlighting(for document: EditorDocument) {
        syntaxSchedulingCoordinator.cancelAll()
        pendingThemeSyntaxController = nil
        pendingThemeDescriptor = nil
        let requestedTheme = ThemeRegistry.descriptor(name: configuration.themeName)
        loadThemeColors(themeName: requestedTheme.name)

        guard let snapshot = document.snapshot else {
            appliedThemeDescriptor = requestedTheme
            largeFilePolicy = .default
            beginOpenTracking()
            refreshPreparedFrame(document: document)
            return
        }

        updateLargeFilePolicy(for: snapshot)
        let reusesExistingSyntax =
            document.syntaxController != nil &&
            document.syntaxThemeName == requestedTheme.name &&
            document.syntaxMaximumTokenizationLineLength == largeFilePolicy.maximumSyntaxLineLength
        _ = document.ensureSyntaxController(
            themeName: requestedTheme.name,
            maximumTokenizationLineLength: largeFilePolicy.maximumSyntaxLineLength
        )
        appliedThemeDescriptor = requestedTheme
        if reusesExistingSyntax {
            beginRevisitTracking()
        } else {
            beginOpenTracking()
        }
        refreshSyntaxViewport(document: document)
    }

    func highlightVisibleLines(document: EditorDocument) {
        guard let snapshot = document.snapshot else {
            refreshPreparedFrame(document: document)
            return
        }

        updateLargeFilePolicy(for: snapshot)
        guard let context = syntaxSchedulingContext(for: document),
              let visibleLineRanges = syntaxSchedulingCoordinatorVisibleRanges(for: context) else {
            metalEditorLogger.error("No tokenization range available")
            return
        }

        syntaxSchedulingCoordinator.refreshViewport { [weak self] in
            self?.syntaxSchedulingContext(for: document)
        }
        refreshPreparedFrame(document: document)
        let highlighted = context.scheduledSyntaxController()?.currentSnapshot().lines(
            in: visibleLineRanges.tokenizationRange
        ).values.sorted {
            $0.lineIndex < $1.lineIndex
        } ?? []
        logHighlightDebug(highlighted, visibleRange: visibleLineRanges.tokenizationRange)
    }

    private func logHighlightDebug(_ highlighted: [SyntaxHighlightedLine], visibleRange: Range<Int>) {
        #if DEBUG
        let highlightedCount = highlighted.count
        let rangeDescription = String(describing: visibleRange)
        metalEditorLogger.debug("Cached highlighted lines: \(highlightedCount, privacy: .public)")
        metalEditorLogger.debug("Cached highlight range: \(rangeDescription, privacy: .public)")
        if let first = highlighted.first {
            let linePreview = String(first.text.prefix(30))
            let tokenCount = first.tokens.count
            metalEditorLogger.debug("First line index: \(first.lineIndex, privacy: .public)")
            metalEditorLogger.debug("First line preview: '\(linePreview, privacy: .public)...'")
            metalEditorLogger.debug("First line token count: \(tokenCount, privacy: .public)")
            for (i, token) in first.tokens.prefix(3).enumerated() {
                let tokenRange = String(describing: token.range)
                metalEditorLogger.debug(
                    "Token \(i, privacy: .public) range: \(tokenRange, privacy: .public)"
                )
                metalEditorLogger.debug(
                    "Token \(i, privacy: .public) fg: \(token.foregroundColor, privacy: .public)"
                )
            }
        }
        #endif
    }

    /// Load colors based on configuration
    private func loadThemeColors(themeName: String? = nil) {
        loadSyntaxThemeColors(themeName: themeName ?? appliedThemeDescriptor.name)
    }

    /// Load colors from the active syntax theme
    private func loadSyntaxThemeColors(themeName: String) {
        let resolvedTheme = ThemeRegistry.resolvedTheme(name: themeName)
        let theme = resolvedTheme.theme

        let bgHex = theme.editorBackground
        backgroundColor = hexToLinearColor(bgHex)
        mtkView.clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: 1.0
        )

        if let lnHex = theme.lineNumberForeground {
            lineNumberColor = hexToLinearColor(lnHex)
        }

        textColor = hexToLinearColor(theme.editorForeground)

        if let cursorHex = theme.cursorColor {
            cursorColor = hexToLinearColor(cursorHex)
        }

        if let selHex = theme.selectionBackground {
            selectionColor = hexToLinearColor(selHex)
        }
    }

    func highlightVisibleLines() {
        guard let document else { return }
        highlightVisibleLines(document: document)
    }

    func scheduleBackgroundHighlight() {
        syntaxSchedulingCoordinator.startBackgroundIfNeeded { [weak self] in
            self?.syntaxSchedulingContext()
        }
    }

    func configurationDidChange() {
        guard let device = mtkView.device else { return }
        let requestedTheme = ThemeRegistry.descriptor(name: configuration.themeName)

        metrics = EditorMetrics.measure(
            fontSize: configuration.fontSize,
            fontName: configuration.fontName
        )

        glyphAtlas = EditorGlyphAtlas(
            device: device,
            fontName: configuration.fontName,
            fontSize: configuration.fontSize,
            scaleFactor: scaleFactor
        )

        lineBuffer?.metrics = metrics
        displayModel.reset()

        if let document = document {
            if requestedTheme.version != appliedThemeDescriptor.version,
               document.syntaxController != nil {
                beginThemeTransition(for: document, theme: requestedTheme)
            } else if document.syntaxController == nil {
                appliedThemeDescriptor = requestedTheme
                pendingThemeDescriptor = nil
                loadThemeColors(themeName: requestedTheme.name)
                startHighlighting(for: document)
            } else {
                pendingThemeDescriptor = nil
                loadThemeColors(themeName: appliedThemeDescriptor.name)
                refreshSyntaxViewport(document: document)
            }
        } else {
            appliedThemeDescriptor = requestedTheme
            pendingThemeDescriptor = nil
            loadThemeColors(themeName: requestedTheme.name)
        }
    }

    func beginOpenTracking() {
        openTrackingGeneration += 1
        openTrackingIdentifier = "editor-open-\(openTrackingGeneration)"
        hasRecordedOpenInteractiveFrame = false
        hasRecordedOpenHighlightedFrame = false
        guard let openTrackingIdentifier else { return }
        SyntaxRuntimeDiagnostics.beginTrackedOpen(
            surface: "editor",
            identifier: openTrackingIdentifier
        )
    }

    func beginRevisitTracking() {
        revisitTrackingGeneration += 1
        revisitTrackingIdentifier = "editor-revisit-\(revisitTrackingGeneration)"
        hasRecordedRevisitInteractiveFrame = false
        hasRecordedRevisitHighlightedFrame = false
        guard let revisitTrackingIdentifier else { return }
        SyntaxRuntimeDiagnostics.beginTrackedRevisit(
            surface: "editor",
            identifier: revisitTrackingIdentifier
        )
    }

    // periphery:ignore - kept for render diagnostics and future viewport transitions
    func displaySyntaxSnapshot(
        for visibleRange: Range<Int>,
        document: EditorDocument
    ) -> SyntaxSnapshot? {
        activatePendingThemeIfReady(document: document, visibleRange: visibleRange)
        return displaySnapshot(for: visibleRange, document: document)
            .visibleRows
            .contains { $0.highlightedLine != nil }
            ? document.syntaxController?.currentSnapshot()
            : nil
    }

    private func scheduledSyntaxController(for document: EditorDocument) -> SyntaxController? {
        pendingThemeSyntaxController ?? document.syntaxController
    }

    private func beginThemeTransition(
        for document: EditorDocument,
        theme: RuntimeThemeDescriptor
    ) {
        guard let snapshot = document.snapshot else { return }
        syntaxSchedulingCoordinator.cancelAll()
        pendingThemeDescriptor = theme
        pendingThemeSyntaxController = SyntaxController(
            documentSnapshot: snapshot,
            language: document.language,
            themeName: theme.name,
            warmCacheIdentity: document.syntaxWarmCacheIdentity,
            maximumTokenizationLineLength: largeFilePolicy.maximumSyntaxLineLength
        )
        refreshSyntaxViewport(document: document)
    }

    private func activatePendingThemeIfReady(
        document: EditorDocument,
        visibleRange: Range<Int>? = nil
    ) {
        guard let pendingThemeSyntaxController,
              let pendingThemeDescriptor else { return }
        let visibleRange = visibleRange ?? lineBuffer?.visibleRange ?? 0..<0
        guard pendingThemeSyntaxController.currentSnapshot().hasActualHighlights(in: visibleRange) else { return }

        document.adoptSyntaxController(
            pendingThemeSyntaxController,
            themeName: pendingThemeDescriptor.name,
            maximumTokenizationLineLength: largeFilePolicy.maximumSyntaxLineLength
        )
        appliedThemeDescriptor = pendingThemeDescriptor
        loadThemeColors(themeName: pendingThemeDescriptor.name)
        self.pendingThemeSyntaxController = nil
        self.pendingThemeDescriptor = nil
    }

    // periphery:ignore - reserved for phased visible-highlight budgeting
    private func startVisibleHighlightBudget(document: EditorDocument) {
        guard document.snapshot != nil else { return }
        syntaxSchedulingCoordinator.refreshViewport { [weak self] in
            self?.syntaxSchedulingContext(for: document)
        }
    }

    private func updateLargeFilePolicy(for documentSnapshot: DocumentSnapshot) {
        largeFilePolicy = EditorLargeFilePolicy(documentSnapshot: documentSnapshot)
    }

    // periphery:ignore - exposed for scheduling tests and viewport heuristics
    func preferredHighlightRange(
        lineBuffer: LineBuffer,
        lineCount: Int
    ) -> Range<Int> {
        syntaxSchedulingCoordinator.preferredHighlightRange(
            lineBuffer: lineBuffer,
            lineCount: lineCount,
            lastScrollDelta: lastHighlightScrollDelta,
            lineHeight: metrics.lineHeight
        )
    }

    private func refreshSyntaxViewport(document: EditorDocument? = nil) {
        let targetDocument = document ?? self.document
        syntaxSchedulingCoordinator.refreshViewport { [weak self] in
            self?.syntaxSchedulingContext(for: targetDocument)
        }
        refreshPreparedFrame(document: targetDocument)
    }

    private var displayRenderContext: EditorDisplayRenderContext {
        EditorDisplayRenderContext(
            themeVersion: appliedThemeDescriptor.version,
            metrics: metrics,
            lineNumberColor: lineNumberColor,
            textColor: textColor,
            backgroundColor: backgroundColor
        )
    }

    private func syntaxSchedulingContext(
        for documentOverride: EditorDocument? = nil
    ) -> EditorSyntaxSchedulingCoordinator.Context? {
        guard let document = documentOverride ?? document,
              let lineBuffer,
              document.snapshot != nil else {
            return nil
        }

        return EditorSyntaxSchedulingCoordinator.Context(
            document: document,
            lineBuffer: lineBuffer,
            scheduledSyntaxController: { [weak self] in
                guard let self else { return nil }
                return self.scheduledSyntaxController(for: document)
            },
            activatePendingThemeIfReady: { [weak self] visibleRange in
                self?.activatePendingThemeIfReady(document: document, visibleRange: visibleRange)
            },
            requestDraw: { [weak self] in
                guard let self else { return }
                self.refreshPreparedFrame(document: document)
                self.mtkView.draw()
            },
            largeFilePolicy: largeFilePolicy,
            highlightBatchSize: highlightBatchSize,
            openHighlightBudgetNanoseconds: openHighlightBudgetNanoseconds,
            lastScrollDelta: lastHighlightScrollDelta,
            lineHeight: metrics.lineHeight
        )
    }

    private func syntaxSchedulingCoordinatorVisibleRanges(
        for context: EditorSyntaxSchedulingCoordinator.Context
    ) -> (visibleRange: Range<Int>, tokenizationRange: Range<Int>)? {
        context.lineBuffer.updateVisibleRange()
        return (context.lineBuffer.visibleRange, context.lineBuffer.tokenizationRange)
    }
}

#endif
