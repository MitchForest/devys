// MetalDiffDocumentView+Highlighting.swift

#if os(macOS)
// periphery:ignore:all - diff highlight scheduling is driven by NSView runtime hooks and tests
import AppKit
import Rendering
import Syntax
import Text

extension MetalDiffDocumentView {
    // periphery:ignore - kept for staged diff highlight scheduling hooks
    func startHighlightTaskIfNeeded() {
        syntaxSchedulingCoordinator.startBackgroundIfNeeded { [weak self] in
            self?.syntaxSchedulingContext()
        }
    }

    // periphery:ignore - kept for staged diff highlight scheduling hooks
    func prefillVisibleHighlightSnapshots() {
        syntaxSchedulingCoordinator.refreshViewport { [weak self] in
            self?.syntaxSchedulingContext()
        }
    }

    // periphery:ignore - kept for explicit visible-range highlight refreshes
    func ensureVisibleHighlights(
        layout: DiffRenderLayout,
        startRow: Int,
        endRow: Int
    ) {
        guard var context = syntaxSchedulingContext() else { return }
        context = DiffSyntaxSchedulingCoordinator.Context(
            layout: layout,
            visibleRect: CGRect(
                x: 0,
                y: CGFloat(startRow) * metrics.lineHeight,
                width: bounds.width,
                height: CGFloat(max(1, endRow - startRow + 1)) * metrics.lineHeight
            ),
            rowHeight: context.rowHeight,
            lastScrollDeltaY: context.lastScrollDeltaY,
            syntaxHighlightingEnabled: context.syntaxHighlightingEnabled,
            highlightBatchSize: context.highlightBatchSize,
            openHighlightBudgetNanoseconds: context.openHighlightBudgetNanoseconds,
            syntaxBacklogPolicy: context.syntaxBacklogPolicy,
            scheduledSyntaxController: context.scheduledSyntaxController,
            activatePendingThemeIfReady: context.activatePendingThemeIfReady,
            requestDraw: context.requestDraw
        )
        syntaxSchedulingCoordinator.refreshViewport { context }
    }

    // periphery:ignore - reserved for phased visible-highlight budgeting
    func startVisibleHighlightBudgetIfNeeded() {
        syntaxSchedulingCoordinator.refreshViewport { [weak self] in
            self?.syntaxSchedulingContext()
        }
    }
}

extension MetalDiffDocumentView {
    typealias HighlightRanges = (base: Range<Int>?, modified: Range<Int>?)
    typealias HighlightSide = DiffSourceSide

    func scheduledSyntaxController(for side: HighlightSide) -> SyntaxController? {
        switch side {
        case .base:
            pendingBaseSyntaxController ?? baseSyntaxController
        case .modified:
            pendingModifiedSyntaxController ?? modifiedSyntaxController
        }
    }

    func activatePendingThemeIfReady(visibleRanges: HighlightRanges) {
        guard pendingThemeName != nil else { return }

        let baseReady = visibleRanges.base.map {
            pendingBaseSyntaxController?.currentSnapshot().hasActualHighlights(in: $0) == true
        } ?? true
        let modifiedReady = visibleRanges.modified.map {
            pendingModifiedSyntaxController?.currentSnapshot().hasActualHighlights(in: $0) == true
        } ?? true
        guard baseReady, modifiedReady else { return }

        if let pendingBaseSyntaxController {
            baseSyntaxController = pendingBaseSyntaxController
        }
        if let pendingModifiedSyntaxController {
            modifiedSyntaxController = pendingModifiedSyntaxController
        }
        if let pendingThemeName {
            themeName = pendingThemeName
        }
        if let pendingThemeVersion {
            themeVersion = pendingThemeVersion
        }
        if let pendingDiffTheme {
            diffTheme = pendingDiffTheme
            applyClearColor()
        }
        pendingBaseSyntaxController = nil
        pendingModifiedSyntaxController = nil
        pendingThemeName = nil
        pendingThemeVersion = nil
        pendingDiffTheme = nil
        refreshPreparedFrame()
    }

    func syntaxSchedulingContext() -> DiffSyntaxSchedulingCoordinator.Context? {
        guard let layout else { return nil }
        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds

        return DiffSyntaxSchedulingCoordinator.Context(
            layout: layout,
            visibleRect: visibleRect,
            rowHeight: metrics.lineHeight,
            lastScrollDeltaY: lastScrollDeltaY,
            syntaxHighlightingEnabled: syntaxHighlightingEnabled,
            highlightBatchSize: highlightBatchSize,
            openHighlightBudgetNanoseconds: openHighlightBudgetNanoseconds,
            syntaxBacklogPolicy: syntaxBacklogPolicy,
            scheduledSyntaxController: { [weak self] side in
                self?.scheduledSyntaxController(for: side)
            },
            activatePendingThemeIfReady: { [weak self] ranges in
                self?.activatePendingThemeIfReady(visibleRanges: ranges)
            },
            requestDraw: { [weak self] in
                self?.refreshPreparedFrame()
                self?.mtkView.draw()
            }
        )
    }

    // periphery:ignore - exposed for scheduling tests and viewport heuristics
    func preferredVisibleRowRange(for layout: DiffRenderLayout) -> ClosedRange<Int>? {
        guard let context = syntaxSchedulingContext() else { return nil }
        let explicitContext = DiffSyntaxSchedulingCoordinator.Context(
            layout: layout,
            visibleRect: context.visibleRect,
            rowHeight: context.rowHeight,
            lastScrollDeltaY: context.lastScrollDeltaY,
            syntaxHighlightingEnabled: context.syntaxHighlightingEnabled,
            highlightBatchSize: context.highlightBatchSize,
            openHighlightBudgetNanoseconds: context.openHighlightBudgetNanoseconds,
            syntaxBacklogPolicy: context.syntaxBacklogPolicy,
            scheduledSyntaxController: context.scheduledSyntaxController,
            activatePendingThemeIfReady: context.activatePendingThemeIfReady,
            requestDraw: context.requestDraw
        )
        return syntaxSchedulingCoordinator.preferredVisibleRowRange(for: explicitContext)
    }

    // periphery:ignore - exposed for scheduling tests and viewport heuristics
    func preferredHighlightRangesForVisibleRows() -> HighlightRanges {
        guard let context = syntaxSchedulingContext() else { return (nil, nil) }
        return syntaxSchedulingCoordinator.visibleHighlightRanges(for: context)
    }

    // periphery:ignore - exposed for scheduling tests and viewport heuristics
    func preferredHighlightRanges(
        for layout: DiffRenderLayout,
        rowRange: ClosedRange<Int>
    ) -> HighlightRanges {
        syntaxSchedulingCoordinator.preferredHighlightRanges(for: layout, rowRange: rowRange)
    }
}
#endif
