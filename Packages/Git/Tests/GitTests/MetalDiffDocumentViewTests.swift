import Testing
import AppKit
import CoreGraphics
import Foundation
import Text
@testable import Syntax
import Rendering
@testable import Git

@MainActor
@Suite("MetalDiffDocumentView Tests")
struct MetalDiffDocumentViewTests {
    @Test("Cold open diff renders readable plain text while syntax is still loading")
    func coldOpenDiffRendersReadablePlainTextWhileSyntaxLoads() async throws {
        await SyntaxControllerTestSupport.setArtificialHighlightDelay(nanoseconds: 100_000_000)

        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        let layout = makeSplitLayout()
        view.updateLanguage("swift")
        SyntaxRuntimeDiagnostics.reset()
        view.updateLayout(layout)
        view.highlightTask?.cancel()
        view.highlightTask = nil

        let initialDisplaySnapshot = visibleDisplaySnapshot(for: view)
        let firstPendingStatus: HighlightStatus? = {
            guard case .split(let splitSnapshot) = initialDisplaySnapshot else { return nil }
            return splitSnapshot.rows.compactMap { $0.left?.content.syntaxStatus }.first
        }()
        let firstPendingGlyph: Character? = {
            guard case .split(let splitSnapshot) = initialDisplaySnapshot else { return nil }
            return splitSnapshot.rows
                .compactMap { $0.left?.content.packet.cells.first?.glyph }
                .first
        }()

        renderCurrentLayout(on: view)

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.syntaxRequestsDuringRender == 0)
        #expect(snapshot.displayPreparationsDuringRender == 0)
        #expect(snapshot.diffProjectionOperationsDuringRender == 0)
        #expect(firstPendingStatus == nil)
        #expect(firstPendingGlyph == "l")
        let cells = renderedCells(from: view.cellBuffer)
        let contentCell = cells.first { $0.flags & EditorCellFlags.lineNumber.rawValue == 0 }
        #expect(contentCell != nil)
        if let contentCell {
            #expect(contentCell.foregroundColor != contentCell.backgroundColor)
        }
        await SyntaxControllerTestSupport.setArtificialHighlightDelay(nanoseconds: nil)
    }

    @Test("Diff render path does not invoke syntax work during render")
    func diffRenderPathAvoidsSyntaxRequestsDuringRender() {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        let layout = makeSplitLayout()
        view.updateLanguage("swift")
        view.updateLayout(layout)
        view.highlightTask?.cancel()
        view.highlightTask = nil

        SyntaxRuntimeDiagnostics.reset()
        SyntaxRuntimeDiagnostics.withStrictRenderAssertionsEnabledForTesting(true) {
            renderCurrentLayout(on: view)
        }

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.syntaxRequestsDuringRender == 0)
        #expect(snapshot.displayPreparationsDuringRender == 0)
        #expect(snapshot.diffProjectionOperationsDuringRender == 0)
    }

    @Test("Diff visible prefetch ranges bias lookahead in scroll direction")
    func diffPrefetchRangesBiasDirection() {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        let layout = makeSplitLayout(repeatedLineCount: 400)
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        scrollView.documentView = view
        view.updateLanguage("swift")
        view.updateLayout(layout)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 1_200))
        view.updateVisibleRect()

        view.lastScrollDeltaY = 200
        let forwardRange = view.preferredVisibleRowRange(for: layout)

        view.lastScrollDeltaY = -200
        let backwardRange = view.preferredVisibleRowRange(for: layout)

        #expect(forwardRange != nil)
        #expect(backwardRange != nil)
        if let forwardRange, let backwardRange {
            #expect(forwardRange.upperBound > backwardRange.upperBound)
            #expect(backwardRange.lowerBound < forwardRange.lowerBound)
        }
    }

    @Test("Diff open budget upgrades visible highlights before background fill")
    func diffOpenBudgetUpgradesVisibleHighlights() async {
        let layout = makeSplitLayout()
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        view.updateLanguage("swift")
        view.updateLayout(layout)
        view.highlightTask?.cancel()
        view.highlightTask = nil

        await view.visibleHighlightBudgetTask?.value

        let visibleRanges = view.preferredHighlightRangesForVisibleRows()
        #expect(view.visibleHighlightBudgetTask == nil)
        if let baseRange = visibleRanges.base {
            #expect(view.baseSyntaxController?.currentSnapshot().hasActualHighlights(in: baseRange) == true)
        }
        if let modifiedRange = visibleRanges.modified {
            #expect(view.modifiedSyntaxController?.currentSnapshot().hasActualHighlights(in: modifiedRange) == true)
        }
    }

    @Test("Theme switch preserves active diff highlights until replacement snapshots are ready")
    func themeSwitchPreservesActiveDiffHighlightsUntilReplacementReady() async throws {
        let layout = makeSplitLayout()
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        view.updateLanguage("swift")
        view.updateLayout(layout)

        let visibleRanges = view.preferredHighlightRangesForVisibleRows()
        if let baseRange = visibleRanges.base {
            view.baseSyntaxController?.noteVisibleRange(SourceLineRange(baseRange.lowerBound, baseRange.upperBound))
            view.baseSyntaxController?.schedule(
                SyntaxRequest(
                    preferredRange: SourceLineRange(baseRange.lowerBound, baseRange.upperBound),
                    batchSize: baseRange.count
                )
            )
            await view.baseSyntaxController?.processNextBatch(
                preferredRange: baseRange,
                batchSize: baseRange.count
            )
        }
        if let modifiedRange = visibleRanges.modified {
            view.modifiedSyntaxController?.noteVisibleRange(SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound))
            view.modifiedSyntaxController?.schedule(
                SyntaxRequest(
                    preferredRange: SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound),
                    batchSize: modifiedRange.count
                )
            )
            await view.modifiedSyntaxController?.processNextBatch(
                preferredRange: modifiedRange,
                batchSize: modifiedRange.count
            )
        }

        let initialBaseController = view.baseSyntaxController
        let initialModifiedController = view.modifiedSyntaxController
        let initialDiffTheme = view.diffTheme
        let lightTheme = try SyntaxTheme.load(name: "devys-light")

        view.updateTheme(DiffTheme(theme: lightTheme), themeName: "devys-light")

        #expect(view.baseSyntaxController === initialBaseController)
        #expect(view.modifiedSyntaxController === initialModifiedController)
        #expect(view.pendingThemeName == "devys-light")
        #expect(view.pendingThemeVersion == 2)
        #expect(view.pendingDiffTheme == DiffTheme(theme: lightTheme))
        #expect(view.pendingBaseSyntaxController != nil || view.pendingModifiedSyntaxController != nil)
        #expect(view.themeName == "devys-dark")
        #expect(view.themeVersion == 1)
        #expect(view.diffTheme == initialDiffTheme)

        if let baseRange = visibleRanges.base {
            view.pendingBaseSyntaxController?.noteVisibleRange(SourceLineRange(baseRange.lowerBound, baseRange.upperBound))
            view.pendingBaseSyntaxController?.schedule(
                SyntaxRequest(
                    preferredRange: SourceLineRange(baseRange.lowerBound, baseRange.upperBound),
                    batchSize: baseRange.count
                )
            )
            await view.pendingBaseSyntaxController?.processNextBatch(
                preferredRange: baseRange,
                batchSize: baseRange.count
            )
        }
        if let modifiedRange = visibleRanges.modified {
            view.pendingModifiedSyntaxController?.noteVisibleRange(SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound))
            view.pendingModifiedSyntaxController?.schedule(
                SyntaxRequest(
                    preferredRange: SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound),
                    batchSize: modifiedRange.count
                )
            )
            await view.pendingModifiedSyntaxController?.processNextBatch(
                preferredRange: modifiedRange,
                batchSize: modifiedRange.count
            )
        }

        view.activatePendingThemeIfReady(visibleRanges: visibleRanges)

        #expect(view.themeName == "devys-light")
        #expect(view.themeVersion == 2)
        #expect(view.diffTheme == DiffTheme(theme: lightTheme))
        #expect(view.pendingThemeName == nil)
        #expect(view.pendingThemeVersion == nil)
        #expect(view.pendingDiffTheme == nil)
        #expect(view.pendingBaseSyntaxController == nil)
        #expect(view.pendingModifiedSyntaxController == nil)
    }

    @Test("Projection changes reuse source-side syntax controllers")
    func projectionChangesReuseSourceSideSyntaxControllers() {
        let diff = makeDiffSnapshot(repeatedLineCount: 8)
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        view.updateLanguage("swift")

        let splitLayout = makeLayout(from: diff, mode: .split, wrapLines: false, splitRatio: 0.5)
        view.updateLayout(splitLayout)
        let initialBaseController = view.baseSyntaxController
        let initialModifiedController = view.modifiedSyntaxController

        let unifiedLayout = makeLayout(from: diff, mode: .unified, wrapLines: true, splitRatio: 0.5)
        view.updateLayout(unifiedLayout)
        #expect(view.baseSyntaxController === initialBaseController)
        #expect(view.modifiedSyntaxController === initialModifiedController)

        let resizedSplitLayout = makeLayout(from: diff, mode: .split, wrapLines: true, splitRatio: 0.68)
        view.updateLayout(resizedSplitLayout)
        #expect(view.baseSyntaxController === initialBaseController)
        #expect(view.modifiedSyntaxController === initialModifiedController)
    }

    @Test("Projection reuse records revisit and visible refresh diagnostics")
    func projectionReuseRecordsRevisitAndRefreshDiagnostics() async {
        let diff = makeDiffSnapshot(repeatedLineCount: 8)
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        view.updateLanguage("swift")

        let splitLayout = makeLayout(from: diff, mode: .split, wrapLines: false, splitRatio: 0.5)
        view.updateLayout(splitLayout)
        await view.visibleHighlightBudgetTask?.value

        let unifiedLayout = makeLayout(from: diff, mode: .unified, wrapLines: true, splitRatio: 0.5)
        SyntaxRuntimeDiagnostics.reset()
        view.updateLayout(unifiedLayout)
        view.draw(in: view.mtkView)

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.surfaceMetrics["diff"]?.completedRevisitInteractiveFrames == 1)
        #expect(snapshot.surfaceMetrics["diff"]?.completedRevisitHighlightedFrames == 1)
        #expect(snapshot.surfaceMetrics["diff"]?.completedVisibleUpdates == 1)
    }

    @Test("Diff display snapshot owns sliced syntax and word-diff state")
    func diffDisplaySnapshotOwnsPreparedVisibleState() async {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        view.updateLanguage("swift")
        view.updateLayout(makeSplitLayout())

        await view.visibleHighlightBudgetTask?.value

        let snapshot = visibleDisplaySnapshot(for: view)
        guard case .split(let splitSnapshot) = snapshot else {
            Issue.record("Expected split display snapshot")
            return
        }

        guard let removedSide = splitSnapshot.rows.compactMap(\.left).first(where: { $0.lineType == .removed }) else {
            Issue.record("Expected removed side in split snapshot")
            return
        }

        guard let addedSide = splitSnapshot.rows.compactMap(\.right).first(where: { $0.lineType == .added }) else {
            Issue.record("Expected added side in split snapshot")
            return
        }

        #expect(removedSide.content.packet.isEmpty == false)
        #expect(addedSide.content.packet.isEmpty == false)
        #expect(removedSide.lineNumberPacket?.isEmpty == false)
        #expect(addedSide.lineNumberPacket?.isEmpty == false)
        #expect(removedSide.content.countsAsActualHighlight)
        #expect(addedSide.content.countsAsActualHighlight)
    }

    @Test("Semantic overlays refine diff syntax packets in display space")
    func semanticOverlaysRefineDiffSyntaxPackets() async {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        view.updateLanguage("swift")
        view.updateLayout(makeSplitLayout())
        await view.visibleHighlightBudgetTask?.value

        view.baseSemanticOverlaySnapshot = SemanticOverlaySnapshot(lines: [
            SemanticOverlayLine(
                lineIndex: 0,
                tokens: [
                    SemanticOverlayToken(
                        range: 0..<3,
                        style: SemanticOverlayStyle(
                            foregroundColor: "#ff0000",
                            fontStyle: [.underline]
                        )
                    )
                ]
            )
        ])
        view.modifiedSemanticOverlaySnapshot = SemanticOverlaySnapshot(lines: [
            SemanticOverlayLine(
                lineIndex: 0,
                tokens: [
                    SemanticOverlayToken(
                        range: 0..<3,
                        style: SemanticOverlayStyle(
                            foregroundColor: "#00ff00",
                            fontStyle: [.underline]
                        )
                    )
                ]
            )
        ])

        let snapshot = visibleDisplaySnapshot(for: view)
        guard case .split(let splitSnapshot) = snapshot else {
            Issue.record("Expected split display snapshot")
            return
        }
        guard let removedSide = splitSnapshot.rows.compactMap(\.left).first(where: { $0.lineType == .removed }),
              let addedSide = splitSnapshot.rows.compactMap(\.right).first(where: { $0.lineType == .added }),
              let removedCell = removedSide.content.packet.cells.first,
              let addedCell = addedSide.content.packet.cells.first else {
            Issue.record("Expected diff content cells")
            return
        }

        #expect(removedCell.foregroundColor == hexToLinearColor("#ff0000"))
        #expect(addedCell.foregroundColor == hexToLinearColor("#00ff00"))
        #expect(removedCell.flags & EditorCellFlags.underline.rawValue != 0)
        #expect(addedCell.flags & EditorCellFlags.underline.rawValue != 0)
    }

    @Test("Large diff policy stages syntax while keeping primary syntax enabled")
    func largeDiffPolicyStagesSyntax() {
        let policy = DiffLargeContentPolicy(totalLines: 1_200)

        #expect(policy.enableSyntaxHighlighting)
        #expect(policy.enableWrap)
        #expect(!policy.enableWordDiff)
        #expect(policy.usesStagedSyntaxLoading)
        #expect(policy.maximumSyntaxLineLength == 1_200)
    }

    @Test("Large diffs keep syntax scheduling windowed around visible rows")
    func largeDiffsKeepSyntaxWindowed() async {
        let policy = DiffLargeContentPolicy(totalLines: 1_200)
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        let layout = makeSplitLayout(repeatedLineCount: 1_199)

        view.updateLanguage("swift")
        view.updateLayout(layout)
        view.updateHighlighting(
            enabled: policy.enableSyntaxHighlighting,
            maxLineLength: policy.maximumSyntaxLineLength,
            backlogPolicy: policy.syntaxBacklogPolicy
        )

        await view.visibleHighlightBudgetTask?.value
        view.highlightTask?.cancel()
        view.highlightTask = nil
        let visibleRanges = view.preferredHighlightRangesForVisibleRows()
        if let baseRange = visibleRanges.base,
           let baseController = view.baseSyntaxController {
            for _ in 0..<8 where baseController.hasScheduledWork(
                preferredRange: SourceLineRange(baseRange.lowerBound, baseRange.upperBound),
                batchSize: view.highlightBatchSize,
                backlogPolicy: policy.syntaxBacklogPolicy
            ) {
                await baseController.processNextBatch(
                    preferredRange: baseRange,
                    batchSize: view.highlightBatchSize,
                    backlogPolicy: policy.syntaxBacklogPolicy
                )
            }
        }
        if let modifiedRange = visibleRanges.modified,
           let modifiedController = view.modifiedSyntaxController {
            for _ in 0..<8 where modifiedController.hasScheduledWork(
                preferredRange: SourceLineRange(modifiedRange.lowerBound, modifiedRange.upperBound),
                batchSize: view.highlightBatchSize,
                backlogPolicy: policy.syntaxBacklogPolicy
            ) {
                await modifiedController.processNextBatch(
                    preferredRange: modifiedRange,
                    batchSize: view.highlightBatchSize,
                    backlogPolicy: policy.syntaxBacklogPolicy
                )
            }
        }

        let baseSnapshot = view.baseSyntaxController?.currentSnapshot()
        let modifiedSnapshot = view.modifiedSyntaxController?.currentSnapshot()
        #expect(view.syntaxBacklogPolicy == policy.syntaxBacklogPolicy)
        #expect(policy.usesStagedSyntaxLoading)
        #expect(baseSnapshot?.line(0)?.status.countsAsActual == true)
        #expect(modifiedSnapshot?.line(0)?.status.countsAsActual == true)
        if case .visibleWindow(let maxLineCount) = policy.syntaxBacklogPolicy,
           let baseRange = visibleRanges.base,
           let modifiedRange = visibleRanges.modified,
           let baseSnapshot,
           let modifiedSnapshot {
            let farBaseLine = baseRange.upperBound + maxLineCount + 32
            let farModifiedLine = modifiedRange.upperBound + maxLineCount + 32
            if farBaseLine < baseSnapshot.lineCount {
                #expect(baseSnapshot.line(farBaseLine) == nil)
            }
            if farModifiedLine < modifiedSnapshot.lineCount {
                #expect(modifiedSnapshot.line(farModifiedLine) == nil)
            }
        }
        view.highlightTask?.cancel()
        view.highlightTask = nil
    }

    @Test("Diff scroll traces record visible sample metrics")
    func diffScrollTracesRecordVisibleSampleMetrics() async {
        let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        defer { cancelBackgroundTasks(on: view) }
        let layout = makeSplitLayout(repeatedLineCount: 300)
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        scrollView.documentView = view

        view.updateLanguage("swift")
        view.updateLayout(layout)
        await view.visibleHighlightBudgetTask?.value

        SyntaxRuntimeDiagnostics.reset()
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 1_000))
        view.updateVisibleRect()
        view.draw(in: view.mtkView)

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.surfaceMetrics["diff"]?.scrollSamples == 1)
        #expect(snapshot.surfaceMetrics["diff"]?.lastScrollDeltaY ?? 0 > 0)
        #expect(snapshot.surfaceMetrics["diff"]?.lastVisibleLoadingLines != nil)
    }

    private func makeSplitLayout(repeatedLineCount: Int = 1) -> DiffRenderLayout {
        let snapshot = makeDiffSnapshot(repeatedLineCount: repeatedLineCount)
        return makeLayout(from: snapshot, mode: .split, wrapLines: false, splitRatio: 0.5)
    }

    private func makeDiffSnapshot(repeatedLineCount: Int = 1) -> DiffSnapshot {
        let repeatedLines = Array(repeating: " print(value)", count: repeatedLineCount).joined(separator: "\n")
        let diff = DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,\(repeatedLineCount + 1) +1,\(repeatedLineCount + 1) @@
        -let value = 1
        +let value = 2
        \(repeatedLines)
        """)
        let repeatedContentLines = Array(repeating: "print(value)", count: repeatedLineCount).joined(separator: "\n")
        return DiffSnapshot(
            from: diff,
            baseContent: ["let value = 1", repeatedContentLines]
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            modifiedContent: ["let value = 2", repeatedContentLines]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        )
    }

    private func makeLayout(
        from snapshot: DiffSnapshot,
        mode: DiffViewMode,
        wrapLines: Bool,
        splitRatio: CGFloat
    ) -> DiffRenderLayout {
        let configuration = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: wrapLines,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        return DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: mode,
            configuration: configuration,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 800,
            splitRatio: splitRatio
        )
    }

    private func renderCurrentLayout(on view: MetalDiffDocumentView) {
        guard let layout = view.layout else {
            Issue.record("Expected diff layout")
            return
        }

        view.underlayBuffer.clear()
        view.cellBuffer.beginFrame()
        view.overlayBuffer.clear()

        let renderMetrics = makeRenderMetrics(for: view)
        let visibleOrigin = CGPoint.zero
        let visibleSize = view.bounds.size
        let displaySnapshot = visibleDisplaySnapshot(for: view)
        let resolvedSnapshot = view.resolve(displaySnapshot)
        switch layout {
        case .unified:
            SyntaxRuntimeDiagnostics.beginRenderPass(surface: "diff")
            guard case .unified(let unifiedSnapshot) = resolvedSnapshot else {
                Issue.record("Expected unified display snapshot")
                SyntaxRuntimeDiagnostics.endRenderPass(surface: "diff")
                return
            }
            view.renderUnified(snapshot: unifiedSnapshot, visibleOrigin: visibleOrigin, visibleSize: visibleSize, metrics: renderMetrics)
            SyntaxRuntimeDiagnostics.endRenderPass(surface: "diff")
        case .split:
            SyntaxRuntimeDiagnostics.beginRenderPass(surface: "diff")
            guard case .split(let splitSnapshot) = resolvedSnapshot else {
                Issue.record("Expected split display snapshot")
                SyntaxRuntimeDiagnostics.endRenderPass(surface: "diff")
                return
            }
            view.renderSplit(snapshot: splitSnapshot, visibleOrigin: visibleOrigin, visibleSize: visibleSize, metrics: renderMetrics)
            SyntaxRuntimeDiagnostics.endRenderPass(surface: "diff")
        }

        view.cellBuffer.endFrame()
        view.cellBuffer.syncToGPU()
    }

    private func visibleDisplaySnapshot(for view: MetalDiffDocumentView) -> DiffDisplaySnapshot {
        guard let layout = view.layout else {
            fatalError("Expected layout")
        }
        let totalRows: Int
        switch layout {
        case .unified(let unified):
            totalRows = unified.rows.count
        case .split(let split):
            totalRows = split.rows.count
        }
        let visibleRowRange = 0...max(0, totalRows - 1)
        let visibleRanges = view.preferredHighlightRanges(for: layout, rowRange: visibleRowRange)
        view.activatePendingThemeIfReady(visibleRanges: visibleRanges)
        return view.displayModel.snapshot(
            view.displaySnapshotRequest(
                layout: layout,
                visibleRowRange: visibleRowRange
            )
        )
    }

    private func renderedCells(from buffer: EditorCellBuffer) -> [EditorCellGPU] {
        let count = buffer.cellCount
        guard count > 0 else { return [] }
        let pointer = buffer.currentBuffer.contents().bindMemory(
            to: EditorCellGPU.self,
            capacity: count
        )
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private func makeRenderMetrics(for view: MetalDiffDocumentView) -> MetalDiffDocumentView.RenderMetrics {
        let scale = Float(view.scaleFactor)
        let cellWidth = Float(view.metrics.cellWidth) * scale
        let lineHeight = Float(view.metrics.lineHeight) * scale
        let gutterPadding = Float(4) * scale
        let lineNumberColumnWidth = view.configuration.showLineNumbers
            ? Float(CGFloat(max(1, view.layout?.maxLineNumberDigits ?? 1)) * view.metrics.cellWidth + 8) * scale
            : 0
        let prefixColumnWidth = view.configuration.showPrefix ? cellWidth * 2 : 0
        let dividerWidth: Float = 1 * scale

        return .init(
            scale: scale,
            cellWidth: cellWidth,
            lineHeight: lineHeight,
            lineNumberColumnWidth: lineNumberColumnWidth,
            prefixColumnWidth: prefixColumnWidth,
            gutterPadding: gutterPadding,
            dividerWidth: dividerWidth
        )
    }

    private func cancelBackgroundTasks(on view: MetalDiffDocumentView) {
        view.highlightTask?.cancel()
        view.highlightTask = nil
        view.visibleHighlightBudgetTask?.cancel()
        view.visibleHighlightBudgetTask = nil
    }
}
