#if os(macOS)
import Foundation
import Syntax
import Text

@MainActor
final class EditorSyntaxSchedulingCoordinator {
    struct Context {
        let document: EditorDocument
        let lineBuffer: LineBuffer
        let scheduledSyntaxController: () -> SyntaxController?
        let activatePendingThemeIfReady: (Range<Int>?) -> Void
        let requestDraw: () -> Void
        let largeFilePolicy: EditorLargeFilePolicy
        let highlightBatchSize: Int
        let openHighlightBudgetNanoseconds: UInt64
        let lastScrollDelta: CGFloat
        let lineHeight: CGFloat
    }

    var backgroundHighlightTask: Task<Void, Never>?
    var visibleHighlightBudgetTask: Task<Void, Never>?

    func cancelAll() {
        backgroundHighlightTask?.cancel()
        backgroundHighlightTask = nil
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
        guard backgroundHighlightTask == nil else { return }
        guard visibleHighlightBudgetTask == nil else { return }

        backgroundHighlightTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let context = contextProvider(),
                      let lineRanges = self.visibleSyntaxRanges(in: context.lineBuffer),
                      let syntaxController = context.scheduledSyntaxController() else {
                    self.backgroundHighlightTask = nil
                    return
                }

                let preferredRange = self.preferredHighlightRange(
                    lineBuffer: context.lineBuffer,
                    lineCount: syntaxController.currentSnapshot().lineCount,
                    lastScrollDelta: context.lastScrollDelta,
                    lineHeight: context.lineHeight
                )
                let sourceRange = SourceLineRange(preferredRange.lowerBound, preferredRange.upperBound)
                let hasScheduledWork = syntaxController.hasScheduledWork(
                    preferredRange: sourceRange,
                    batchSize: context.highlightBatchSize,
                    backlogPolicy: context.largeFilePolicy.syntaxBacklogPolicy
                )
                guard hasScheduledWork else {
                    context.activatePendingThemeIfReady(lineRanges.visibleRange)
                    self.backgroundHighlightTask = nil
                    return
                }

                syntaxController.noteVisibleRange(sourceRange)
                syntaxController.schedule(
                    SyntaxRequest(
                        preferredRange: sourceRange,
                        batchSize: context.highlightBatchSize,
                        backlogPolicy: context.largeFilePolicy.syntaxBacklogPolicy
                    )
                )
                context.activatePendingThemeIfReady(lineRanges.visibleRange)

                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            self.backgroundHighlightTask = nil
        }
    }

    private func prefillVisibleSnapshots(context: Context) {
        guard let lineRanges = visibleSyntaxRanges(in: context.lineBuffer) else { return }
        _ = primeVisibleSyntax(
            context: context,
            visibleRange: lineRanges.visibleRange,
            tokenizationRange: lineRanges.tokenizationRange
        )
        context.activatePendingThemeIfReady(lineRanges.visibleRange)
    }

    private func startVisibleHighlightBudgetIfNeeded(
        contextProvider: @escaping @MainActor () -> Context?
    ) {
        visibleHighlightBudgetTask?.cancel()
        visibleHighlightBudgetTask = nil

        guard let context = contextProvider(),
              let lineRanges = visibleSyntaxRanges(in: context.lineBuffer),
              let syntaxController = context.scheduledSyntaxController() else {
            startBackgroundIfNeeded(contextProvider: contextProvider)
            return
        }

        if syntaxController.currentSnapshot().hasActualHighlights(in: lineRanges.visibleRange) {
            startBackgroundIfNeeded(contextProvider: contextProvider)
            return
        }

        let trackedDocument = context.document
        visibleHighlightBudgetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.visibleHighlightBudgetTask = nil
                self.startBackgroundIfNeeded(contextProvider: contextProvider)
            }

            guard let currentContext = contextProvider(),
                  currentContext.document === trackedDocument,
                  let currentLineRanges = self.visibleSyntaxRanges(in: currentContext.lineBuffer),
                  let currentSyntaxController = currentContext.scheduledSyntaxController() else {
                return
            }

            let visibleSourceRange = SourceLineRange(
                currentLineRanges.visibleRange.lowerBound,
                currentLineRanges.visibleRange.upperBound
            )
            let tokenizationSourceRange = SourceLineRange(
                currentLineRanges.tokenizationRange.lowerBound,
                currentLineRanges.tokenizationRange.upperBound
            )

            _ = await currentSyntaxController.prepareActualHighlights(
                visibleRange: visibleSourceRange,
                preferredRange: tokenizationSourceRange,
                batchSize: max(currentContext.highlightBatchSize, currentLineRanges.visibleRange.count),
                budgetNanoseconds: currentContext.openHighlightBudgetNanoseconds,
                backlogPolicy: currentContext.largeFilePolicy.syntaxBacklogPolicy
            )

            currentContext.activatePendingThemeIfReady(currentLineRanges.visibleRange)
            currentContext.requestDraw()
        }
    }

    private func visibleSyntaxRanges(
        in lineBuffer: LineBuffer
    ) -> (visibleRange: Range<Int>, tokenizationRange: Range<Int>)? {
        lineBuffer.updateVisibleRange()
        return (lineBuffer.visibleRange, lineBuffer.tokenizationRange)
    }

    @discardableResult
    private func primeVisibleSyntax(
        context: Context,
        visibleRange: Range<Int>,
        tokenizationRange: Range<Int>
    ) -> SyntaxController? {
        let syntaxController = context.scheduledSyntaxController()
        let visibleSourceRange = SourceLineRange(visibleRange.lowerBound, visibleRange.upperBound)
        let tokenizationSourceRange = SourceLineRange(
            tokenizationRange.lowerBound,
            tokenizationRange.upperBound
        )
        syntaxController?.noteVisibleRange(visibleSourceRange)
        syntaxController?.schedule(
            SyntaxRequest(
                preferredRange: tokenizationSourceRange,
                batchSize: max(context.highlightBatchSize, visibleRange.count),
                backlogPolicy: context.largeFilePolicy.syntaxBacklogPolicy
            )
        )
        return syntaxController
    }

    func preferredHighlightRange(
        lineBuffer: LineBuffer,
        lineCount: Int,
        lastScrollDelta: CGFloat,
        lineHeight: CGFloat
    ) -> Range<Int> {
        lineBuffer.updateVisibleRange()
        let visibleRange = lineBuffer.visibleRange
        let baseBuffer = lineBuffer.bufferLines
        let velocityLines = max(0, Int(abs(lastScrollDelta) / max(1, lineHeight)))
        let lookahead = max(baseBuffer, min(200, baseBuffer + velocityLines * 8))
        let trailing = max(baseBuffer / 2, min(lookahead, 24))

        if lastScrollDelta >= 0 {
            let start = max(0, visibleRange.lowerBound - trailing)
            let end = min(lineCount, visibleRange.upperBound + lookahead)
            return start..<end
        }

        let start = max(0, visibleRange.lowerBound - lookahead)
        let end = min(lineCount, visibleRange.upperBound + trailing)
        return start..<end
    }
}
#endif
