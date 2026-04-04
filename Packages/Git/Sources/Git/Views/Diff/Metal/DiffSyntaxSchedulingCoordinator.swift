#if os(macOS)
import CoreGraphics
import Syntax
import Text

@MainActor
final class DiffSyntaxSchedulingCoordinator {
    typealias HighlightRanges = (base: Range<Int>?, modified: Range<Int>?)

    struct Context {
        let layout: DiffRenderLayout
        let visibleRect: CGRect
        let rowHeight: CGFloat
        let lastScrollDeltaY: CGFloat
        let syntaxHighlightingEnabled: Bool
        let highlightBatchSize: Int
        let openHighlightBudgetNanoseconds: UInt64
        let syntaxBacklogPolicy: SyntaxBacklogPolicy
        let scheduledSyntaxController: (DiffSourceSide) -> SyntaxController?
        let activatePendingThemeIfReady: (HighlightRanges) -> Void
        let requestDraw: () -> Void
    }

    var highlightTask: Task<Void, Never>?
    var visibleHighlightBudgetTask: Task<Void, Never>?

    func cancelAll() {
        highlightTask?.cancel()
        highlightTask = nil
        visibleHighlightBudgetTask?.cancel()
        visibleHighlightBudgetTask = nil
    }

    func refreshViewport(
        contextProvider: @escaping @MainActor () -> Context?
    ) {
        guard let context = contextProvider() else { return }
        prefillVisibleSnapshots(context: context)
        startVisibleHighlightBudgetIfNeeded(contextProvider: contextProvider)
    }

    func startBackgroundIfNeeded(
        contextProvider: @escaping @MainActor () -> Context?
    ) {
        guard highlightTask == nil else { return }
        guard visibleHighlightBudgetTask == nil else { return }
        guard let context = contextProvider(), context.syntaxHighlightingEnabled else { return }

        highlightTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let currentContext = contextProvider(),
                      currentContext.syntaxHighlightingEnabled else {
                    self.highlightTask = nil
                    return
                }

                let visibleRanges = self.visibleHighlightRanges(for: currentContext)
                let ranges = self.preferredHighlightRangesForVisibleRows(context: currentContext)
                self.scheduleSyntaxWork(
                    on: currentContext.scheduledSyntaxController(.base),
                    visibleRange: visibleRanges.base,
                    preferredRange: ranges.base,
                    batchSize: currentContext.highlightBatchSize,
                    backlogPolicy: currentContext.syntaxBacklogPolicy
                )
                self.scheduleSyntaxWork(
                    on: currentContext.scheduledSyntaxController(.modified),
                    visibleRange: visibleRanges.modified,
                    preferredRange: ranges.modified,
                    batchSize: currentContext.highlightBatchSize,
                    backlogPolicy: currentContext.syntaxBacklogPolicy
                )
                currentContext.activatePendingThemeIfReady(visibleRanges)

                let basePending = self.hasScheduledSyntaxWork(
                    on: currentContext.scheduledSyntaxController(.base),
                    preferredRange: ranges.base,
                    batchSize: currentContext.highlightBatchSize,
                    backlogPolicy: currentContext.syntaxBacklogPolicy
                )
                let modifiedPending = self.hasScheduledSyntaxWork(
                    on: currentContext.scheduledSyntaxController(.modified),
                    preferredRange: ranges.modified,
                    batchSize: currentContext.highlightBatchSize,
                    backlogPolicy: currentContext.syntaxBacklogPolicy
                )
                if !basePending && !modifiedPending {
                    self.highlightTask = nil
                    return
                }

                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            self.highlightTask = nil
        }
    }

    private func prefillVisibleSnapshots(context: Context) {
        let visibleRanges = visibleHighlightRanges(for: context)
        let scheduledRanges = preferredHighlightRangesForVisibleRows(context: context)

        if let baseRange = scheduledRanges.base {
            let request = SyntaxRequest(
                preferredRange: SourceLineRange(baseRange.lowerBound, baseRange.upperBound),
                batchSize: context.highlightBatchSize,
                backlogPolicy: context.syntaxBacklogPolicy
            )
            if let visibleBaseRange = visibleRanges.base {
                context.scheduledSyntaxController(.base)?.noteVisibleRange(
                    SourceLineRange(visibleBaseRange.lowerBound, visibleBaseRange.upperBound)
                )
            }
            context.scheduledSyntaxController(.base)?.schedule(request)
        }

        if let modifiedRange = scheduledRanges.modified {
            let request = SyntaxRequest(
                preferredRange: SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound),
                batchSize: context.highlightBatchSize,
                backlogPolicy: context.syntaxBacklogPolicy
            )
            if let visibleModifiedRange = visibleRanges.modified {
                context.scheduledSyntaxController(.modified)?.noteVisibleRange(
                    SourceLineRange(visibleModifiedRange.lowerBound, visibleModifiedRange.upperBound)
                )
            }
            context.scheduledSyntaxController(.modified)?.schedule(request)
        }

        context.activatePendingThemeIfReady(visibleRanges)
    }

    private func startVisibleHighlightBudgetIfNeeded(
        contextProvider: @escaping @MainActor () -> Context?
    ) {
        visibleHighlightBudgetTask?.cancel()
        visibleHighlightBudgetTask = nil

        guard let context = contextProvider(), context.syntaxHighlightingEnabled else {
            startBackgroundIfNeeded(contextProvider: contextProvider)
            return
        }

        let visibleRanges = visibleHighlightRanges(for: context)
        let baseNeedsBudget = visibleRanges.base.map {
            context.scheduledSyntaxController(.base)?.currentSnapshot().hasActualHighlights(in: $0) != true
        } ?? false
        let modifiedNeedsBudget = visibleRanges.modified.map {
            context.scheduledSyntaxController(.modified)?.currentSnapshot().hasActualHighlights(in: $0) != true
        } ?? false

        guard baseNeedsBudget || modifiedNeedsBudget else {
            startBackgroundIfNeeded(contextProvider: contextProvider)
            return
        }

        visibleHighlightBudgetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.visibleHighlightBudgetTask = nil
                self.startBackgroundIfNeeded(contextProvider: contextProvider)
            }

            guard let currentContext = contextProvider() else { return }
            let currentVisibleRanges = self.visibleHighlightRanges(for: currentContext)

            if let baseRange = currentVisibleRanges.base,
               let baseSyntaxController = currentContext.scheduledSyntaxController(.base) {
                _ = await baseSyntaxController.prepareActualHighlights(
                    visibleRange: SourceLineRange(baseRange.lowerBound, baseRange.upperBound),
                    preferredRange: SourceLineRange(baseRange.lowerBound, baseRange.upperBound),
                    batchSize: max(currentContext.highlightBatchSize, baseRange.count),
                    budgetNanoseconds: currentContext.openHighlightBudgetNanoseconds,
                    backlogPolicy: currentContext.syntaxBacklogPolicy
                )
            }

            if let modifiedRange = currentVisibleRanges.modified,
               let modifiedSyntaxController = currentContext.scheduledSyntaxController(.modified) {
                _ = await modifiedSyntaxController.prepareActualHighlights(
                    visibleRange: SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound),
                    preferredRange: SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound),
                    batchSize: max(currentContext.highlightBatchSize, modifiedRange.count),
                    budgetNanoseconds: currentContext.openHighlightBudgetNanoseconds,
                    backlogPolicy: currentContext.syntaxBacklogPolicy
                )
            }

            currentContext.activatePendingThemeIfReady(currentVisibleRanges)
            currentContext.requestDraw()
        }
    }

    private func scheduleSyntaxWork(
        on syntaxController: SyntaxController?,
        visibleRange: Range<Int>?,
        preferredRange: Range<Int>?,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy
    ) {
        guard let syntaxController else { return }
        let snapshot = syntaxController.currentSnapshot()
        let range = preferredRange ?? 0..<snapshot.lineCount
        let request = SyntaxRequest(
            preferredRange: SourceLineRange(range.lowerBound, range.upperBound),
            batchSize: batchSize,
            backlogPolicy: backlogPolicy
        )
        if let visibleRange {
            syntaxController.noteVisibleRange(
                SourceLineRange(visibleRange.lowerBound, visibleRange.upperBound)
            )
        }
        syntaxController.schedule(request)
    }

    private func hasScheduledSyntaxWork(
        on syntaxController: SyntaxController?,
        preferredRange: Range<Int>?,
        batchSize: Int,
        backlogPolicy: SyntaxBacklogPolicy
    ) -> Bool {
        guard let syntaxController else { return false }
        let snapshot = syntaxController.currentSnapshot()
        let range = preferredRange ?? 0..<snapshot.lineCount
        return syntaxController.hasScheduledWork(
            preferredRange: SourceLineRange(range.lowerBound, range.upperBound),
            batchSize: batchSize,
            backlogPolicy: backlogPolicy
        )
    }

    func preferredHighlightRangesForVisibleRows(
        context: Context
    ) -> HighlightRanges {
        guard let rowRange = preferredVisibleRowRange(for: context) else { return (nil, nil) }
        return preferredHighlightRanges(for: context.layout, rowRange: rowRange)
    }

    func visibleHighlightRanges(
        for context: Context
    ) -> HighlightRanges {
        guard let rowRange = visibleRowRange(for: context) else { return (nil, nil) }
        return preferredHighlightRanges(for: context.layout, rowRange: rowRange)
    }

    func visibleRowRange(
        for context: Context
    ) -> ClosedRange<Int>? {
        let totalRows: Int
        switch context.layout {
        case .unified(let unified):
            totalRows = unified.rows.count
        case .split(let split):
            totalRows = split.rows.count
        }
        guard totalRows > 0 else { return nil }

        let startRow = max(0, Int(floor(context.visibleRect.minY / context.rowHeight)))
        let endRow = min(totalRows - 1, Int(ceil(context.visibleRect.maxY / context.rowHeight)))
        guard startRow <= endRow else { return nil }
        return startRow...endRow
    }

    func preferredVisibleRowRange(
        for context: Context
    ) -> ClosedRange<Int>? {
        guard let visibleRowRange = visibleRowRange(for: context) else { return nil }
        let totalRows: Int
        switch context.layout {
        case .unified(let unified):
            totalRows = unified.rows.count
        case .split(let split):
            totalRows = split.rows.count
        }
        let startRow = visibleRowRange.lowerBound
        let endRow = visibleRowRange.upperBound

        let visibleRowCount = max(1, endRow - startRow + 1)
        let velocityRows = max(0, Int(abs(context.lastScrollDeltaY) / max(1, context.rowHeight)))
        let lookahead = min(visibleRowCount * 4, visibleRowCount + velocityRows * 2 + 12)
        let trailing = max(6, lookahead / 3)

        if context.lastScrollDeltaY >= 0 {
            return max(0, startRow - trailing)...min(totalRows - 1, endRow + lookahead)
        }

        return max(0, startRow - lookahead)...min(totalRows - 1, endRow + trailing)
    }

    func preferredHighlightRanges(
        for layout: DiffRenderLayout,
        rowRange: ClosedRange<Int>
    ) -> HighlightRanges {
        var baseLower: Int?
        var baseUpper: Int?
        var modifiedLower: Int?
        var modifiedUpper: Int?

        func include(_ segment: DiffHighlightSegment?) {
            guard let segment else { return }
            switch segment.side {
            case .base:
                baseLower = min(baseLower ?? segment.sourceLineIndex, segment.sourceLineIndex)
                baseUpper = max(baseUpper ?? segment.sourceLineIndex, segment.sourceLineIndex)
            case .modified:
                modifiedLower = min(modifiedLower ?? segment.sourceLineIndex, segment.sourceLineIndex)
                modifiedUpper = max(modifiedUpper ?? segment.sourceLineIndex, segment.sourceLineIndex)
            }
        }

        switch layout {
        case .unified(let unified):
            guard !unified.rows.isEmpty else { return (nil, nil) }
            for rowIndex in rowRange {
                include(unified.rows[rowIndex].highlightSegment)
            }
        case .split(let split):
            guard !split.rows.isEmpty else { return (nil, nil) }
            for rowIndex in rowRange {
                let row = split.rows[rowIndex]
                include(row.left?.highlightSegment)
                include(row.right?.highlightSegment)
            }
        }

        let baseRange = baseLower.flatMap { lower in
            baseUpper.map { upper in lower..<(upper + 1) }
        }
        let modifiedRange = modifiedLower.flatMap { lower in
            modifiedUpper.map { upper in lower..<(upper + 1) }
        }

        return (baseRange, modifiedRange)
    }
}
#endif
