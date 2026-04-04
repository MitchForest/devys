import Testing
import CoreGraphics
import Rendering
import Text
@testable import Syntax
@testable import Editor

@MainActor
@Suite("MetalEditorView Tests")
struct MetalEditorViewTests {
    @Test("Cold open renders readable plain text while syntax is still loading")
    func coldOpenRendersReadablePlainTextWhileSyntaxLoads() async throws {
        await SyntaxControllerTestSupport.setArtificialHighlightDelay(nanoseconds: 100_000_000)

        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            """,
            language: "swift"
        )

        SyntaxRuntimeDiagnostics.reset()
        view.document = document
        view.backgroundHighlightTask?.cancel()
        view.backgroundHighlightTask = nil
        view.draw(in: view.mtkView)

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.syntaxRequestsDuringRender == 0)
        #expect(snapshot.displayPreparationsDuringRender == 0)
        #expect(snapshot.loadingPlaceholderLines == 0)
        #expect(document.syntaxController?.currentSnapshot().hasRenderableHighlights(in: 0..<document.lineCount) == false)

        let cells = renderedCells(from: view.cellBuffer)
        let contentCell = cells.first { $0.flags & EditorCellFlags.lineNumber.rawValue == 0 }
        #expect(contentCell != nil)
        if let contentCell {
            #expect(contentCell.foregroundColor != view.backgroundColor)
            #expect(contentCell.backgroundColor == view.backgroundColor)
        }

        await SyntaxControllerTestSupport.setArtificialHighlightDelay(nanoseconds: nil)
    }

    @Test("Editor draw path does not invoke syntax work during render")
    func drawPathAvoidsSyntaxRequestsDuringRender() {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            """,
            language: "swift"
        )

        view.document = document
        view.backgroundHighlightTask?.cancel()
        view.backgroundHighlightTask = nil

        SyntaxRuntimeDiagnostics.reset()
        SyntaxRuntimeDiagnostics.withStrictRenderAssertionsEnabledForTesting(true) {
            view.draw(in: view.mtkView)
        }

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.syntaxRequestsDuringRender == 0)
        #expect(snapshot.displayPreparationsDuringRender == 0)
    }

    @Test("Highlight prefetch range biases lookahead in scroll direction")
    func highlightPrefetchRangeBiasesDirection() {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: Array(repeating: "let value = 1", count: 300).joined(separator: "\n"),
            language: "swift"
        )

        view.document = document
        view.backgroundHighlightTask?.cancel()
        view.backgroundHighlightTask = nil
        guard let lineBuffer = view.lineBuffer else {
            Issue.record("Expected line buffer")
            return
        }

        lineBuffer.scrollOffset = 2_000
        lineBuffer.updateVisibleRange()

        view.lastHighlightScrollDelta = 120
        let forwardRange = view.preferredHighlightRange(
            lineBuffer: lineBuffer,
            lineCount: document.lineCount
        )

        view.lastHighlightScrollDelta = -120
        let backwardRange = view.preferredHighlightRange(
            lineBuffer: lineBuffer,
            lineCount: document.lineCount
        )

        #expect(forwardRange.upperBound > backwardRange.upperBound)
        #expect(backwardRange.lowerBound < forwardRange.lowerBound)
    }

    @Test("Open budget upgrades visible highlights before background fill")
    func openBudgetUpgradesVisibleHighlights() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            """,
            language: "swift"
        )

        view.document = document
        view.backgroundHighlightTask?.cancel()
        view.backgroundHighlightTask = nil

        await view.visibleHighlightBudgetTask?.value

        #expect(view.visibleHighlightBudgetTask == nil)
        #expect(document.syntaxController?.currentSnapshot().hasActualHighlights(in: 0..<document.lineCount) == true)
    }

    @Test("Preview-backed documents stay on the real editor and defer syntax until activation")
    func previewBackedDocumentsDeferSyntaxUntilActivation() async throws {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument.makePreviewDocument(
            content: "let preview = true\n",
            language: "swift"
        )

        view.document = document
        view.backgroundHighlightTask?.cancel()
        view.backgroundHighlightTask = nil
        view.draw(in: view.mtkView)

        let previewSnapshot = view.displaySnapshot(for: 0..<document.lineCount, document: document)
        #expect(document.syntaxController == nil)
        #expect(view.visibleHighlightBudgetTask == nil)
        #expect(previewSnapshot.visibleRows.map(\.text) == ["let preview = true", ""])

        let expectedVersion = document.documentVersion
        let prepared = try await EditorDocument.prepareTextDocument(content: document.content)
        try await document.activatePreparedTextDocument(
            prepared,
            expectedVersion: expectedVersion
        )

        view.observedDocumentLoadStateRevision = document.loadStateRevision - 1
        view.document = document
        await view.visibleHighlightBudgetTask?.value

        #expect(document.snapshot != nil)
        #expect(document.syntaxController != nil)
        #expect(document.syntaxController?.currentSnapshot().hasActualHighlights(in: 0..<document.lineCount) == true)
    }

    @Test("Reattaching a document reuses existing syntax state")
    func reattachingDocumentReusesSyntaxState() async {
        EditorDisplayModel.resetSharedCacheForTesting()
        SyntaxController.resetWarmCacheForTesting()
        SyntaxRuntimeDiagnostics.reset()

        let firstView = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            """,
            language: "swift"
        )

        firstView.document = document
        await firstView.visibleHighlightBudgetTask?.value

        guard let existingSyntaxController = document.syntaxController else {
            Issue.record("Expected document syntax controller")
            return
        }
        _ = firstView.displaySnapshot(for: 0..<document.lineCount, document: document)

        let secondView = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        secondView.document = document
        secondView.displayModel.reset()
        let revisitedSnapshot = secondView.displaySnapshot(for: 0..<document.lineCount, document: document)
        secondView.draw(in: secondView.mtkView)
        let diagnostics = SyntaxRuntimeDiagnostics.snapshot()

        #expect(document.syntaxController === existingSyntaxController)
        #expect(secondView.visibleHighlightBudgetTask == nil)
        #expect(document.syntaxThemeName == "devys-dark")
        #expect(existingSyntaxController.currentSnapshot().hasActualHighlights(in: 0..<document.lineCount))
        #expect(revisitedSnapshot.visibleRows.allSatisfy { $0.highlightedLine?.status.countsAsActual == true })
        #expect(diagnostics.surfaceMetrics["editor"]?.completedRevisitInteractiveFrames == 1)
        #expect(diagnostics.surfaceMetrics["editor"]?.completedRevisitHighlightedFrames == 1)
    }

    @Test("Fresh reopen of unchanged content reuses warm syntax and shared display rows")
    func freshReopenReusesWarmSyntaxAndDisplayRows() async {
        EditorDisplayModel.resetSharedCacheForTesting()
        SyntaxController.resetWarmCacheForTesting()
        SyntaxRuntimeDiagnostics.reset()

        let content = """
        let value = 1
        let other = value + 1
        """

        let firstView = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let firstDocument = EditorDocument(content: content, language: "swift")
        firstView.document = firstDocument
        await firstView.visibleHighlightBudgetTask?.value

        let firstSnapshot = firstView.displaySnapshot(
            for: 0..<firstDocument.lineCount,
            document: firstDocument
        )
        #expect(firstSnapshot.visibleRows.allSatisfy { $0.highlightedLine?.status.countsAsActual == true })

        let reopenedDocument = EditorDocument(content: content, language: "swift")
        #expect(reopenedDocument.reopenIdentity == firstDocument.reopenIdentity)

        let reopenedView = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        reopenedView.document = reopenedDocument

        #expect(reopenedView.visibleHighlightBudgetTask == nil)
        #expect(reopenedDocument.syntaxController?.currentSnapshot().hasActualHighlights(in: 0..<reopenedDocument.lineCount) == true)

        reopenedView.displayModel.reset()
        let reopenedSnapshot = reopenedView.displaySnapshot(
            for: 0..<reopenedDocument.lineCount,
            document: reopenedDocument
        )
        reopenedView.draw(in: reopenedView.mtkView)

        let diagnostics = SyntaxRuntimeDiagnostics.snapshot()
        #expect(reopenedView.displayModel.lastSnapshotUsedSharedCache)
        #expect(reopenedSnapshot.visibleRows.allSatisfy { $0.highlightedLine?.status.countsAsActual == true })
        #expect(diagnostics.syntaxRequestsDuringRender == 0)
        #expect(diagnostics.displayPreparationsDuringRender == 0)
    }

    @Test("Theme switch preserves active highlights until replacement snapshots are ready")
    func themeSwitchPreservesActiveHighlightsUntilReplacementReady() async throws {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            """,
            language: "swift"
        )

        view.document = document
        guard let initialModel = document.syntaxController else {
            Issue.record("Expected initial syntax controller")
            return
        }

        initialModel.noteVisibleRange(SourceLineRange(0, document.lineCount))
        initialModel.schedule(
            SyntaxRequest(
                preferredRange: SourceLineRange(0, document.lineCount),
                batchSize: document.lineCount
            )
        )
        await initialModel.processNextBatch(
            preferredRange: 0..<document.lineCount,
            batchSize: document.lineCount
        )

        var configuration = view.configuration
        configuration.colorScheme = .light
        view.configuration = configuration

        #expect(document.syntaxController === initialModel)
        #expect(view.pendingThemeSyntaxController != nil)
        #expect(view.appliedThemeDescriptor.name == "devys-dark")
        #expect(view.appliedThemeDescriptor.version == 1)

        guard let pendingModel = view.pendingThemeSyntaxController else {
            Issue.record("Expected pending theme syntax controller")
            return
        }

        pendingModel.noteVisibleRange(SourceLineRange(0, document.lineCount))
        pendingModel.schedule(
            SyntaxRequest(
                preferredRange: SourceLineRange(0, document.lineCount),
                batchSize: document.lineCount
            )
        )
        await pendingModel.processNextBatch(
            preferredRange: 0..<document.lineCount,
            batchSize: document.lineCount
        )

        let displayedSnapshot = view.displaySyntaxSnapshot(
            for: 0..<document.lineCount,
            document: document
        )

        #expect(displayedSnapshot?.hasActualHighlights(in: 0..<document.lineCount) == true)
        #expect(document.syntaxController === pendingModel)
        #expect(view.pendingThemeSyntaxController == nil)
        #expect(view.pendingThemeDescriptor == nil)
        #expect(view.appliedThemeDescriptor.name == "devys-light")
        #expect(view.appliedThemeDescriptor.version == 2)
    }

    @Test("Display snapshot tracks visible rows and upgraded highlight state")
    func displaySnapshotTracksVisibleRowsAndHighlightState() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            """,
            language: "swift"
        )

        view.document = document
        let initialSnapshot = view.displaySnapshot(for: 0..<document.lineCount, document: document)
        #expect(initialSnapshot.visibleRows.map(\.lineIndex) == [0, 1])
        #expect(initialSnapshot.visibleRows.contains { $0.highlightedLine?.status.countsAsActual != true })

        await view.visibleHighlightBudgetTask?.value

        let highlightedSnapshot = view.displaySnapshot(for: 0..<document.lineCount, document: document)
        #expect(highlightedSnapshot.documentVersion == document.snapshot?.version)
        #expect(highlightedSnapshot.visibleRows.allSatisfy { $0.highlightedLine?.status.countsAsActual == true })
    }

    @Test("Semantic overlays refine editor syntax packets in display space")
    func semanticOverlaysRefineEditorSyntaxPackets() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            """,
            language: "swift"
        )

        view.document = document
        await view.visibleHighlightBudgetTask?.value
        view.semanticOverlaySnapshot = SemanticOverlaySnapshot(lines: [
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

        let snapshot = view.displaySnapshot(for: 0..<document.lineCount, document: document)
        guard let firstCell = snapshot.visibleRows.first?.contentPacket.cells.first else {
            Issue.record("Expected first content cell")
            return
        }

        #expect(firstCell.foregroundColor == hexToLinearColor("#ff0000"))
        #expect(firstCell.flags & EditorCellFlags.underline.rawValue != 0)
    }

    @Test("Large editor files keep syntax scheduling windowed around the viewport")
    func largeEditorFilesKeepSyntaxWindowed() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: Array(repeating: "let value = 1", count: 6_000).joined(separator: "\n"),
            language: "swift"
        )

        view.document = document
        view.backgroundHighlightTask?.cancel()
        view.backgroundHighlightTask = nil

        await view.visibleHighlightBudgetTask?.value
        view.scheduleBackgroundHighlight()
        await view.backgroundHighlightTask?.value

        #expect(view.largeFilePolicy.usesWindowedSyntax)
        #expect(document.syntaxController?.currentSnapshot().hasActualHighlights(in: 0..<30) == true)
        #expect(document.syntaxController?.currentSnapshot().line(5_500) == nil)
    }

    @Test("Visible editor edits keep stale-or-actual highlights instead of plain text")
    func visibleEditorEditsKeepStaleOrActualHighlights() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: """
            let value = 1
            let other = value + 1
            let third = other + 1
            let fourth = third + 1
            print(fourth)
            """,
            language: "swift"
        )

        view.document = document
        await view.visibleHighlightBudgetTask?.value

        document.replace(
            TextRange(
                start: TextPosition(line: 0, column: 4),
                end: TextPosition(line: 0, column: 9)
            ),
            with: "renamedValue"
        )
        document.syncSyntaxController(dirtyFrom: 0)
        view.pendingVisibleEditIdentifier = "editor-edit-test"
        SyntaxRuntimeDiagnostics.beginVisibleEdit(surface: "editor", identifier: "editor-edit-test")
        view.highlightVisibleLines(document: document)

        let staleSnapshot = view.displaySnapshot(for: 0..<document.lineCount, document: document)
        #expect(staleSnapshot.visibleRows.isEmpty == false)
        let trailingRow = staleSnapshot.visibleRows.first { $0.lineIndex == 4 }
        #expect(trailingRow?.highlightedLine?.status == .stale || trailingRow?.highlightedLine?.status == .actual)
        #expect(trailingRow?.highlightedLine?.status.isRenderable == true)
        #expect(staleSnapshot.visibleRows.allSatisfy { $0.contentPacket.isEmpty == false })
    }

    @Test("Editor scroll traces record visible sample metrics")
    func editorScrollTracesRecordVisibleSampleMetrics() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let document = EditorDocument(
            content: Array(repeating: "let value = 1", count: 200).joined(separator: "\n"),
            language: "swift"
        )

        SyntaxRuntimeDiagnostics.reset()
        view.document = document
        await view.visibleHighlightBudgetTask?.value
        view.lastHighlightScrollDelta = 96
        view.shouldRecordScrollTrace = true
        view.draw(in: view.mtkView)

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.surfaceMetrics["editor"]?.scrollSamples == 1)
        #expect(snapshot.surfaceMetrics["editor"]?.lastScrollDeltaY == 96)
        #expect(snapshot.surfaceMetrics["editor"]?.lastPrefetchHits ?? 0 > 0)
    }

    @Test("Editor marks oversized lines as intentionally limited")
    func editorMarksOversizedLinesAsIntentionallyLimited() async {
        let view = MetalEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        let oversizedLine = String(repeating: "x", count: 1_600)
        let document = EditorDocument(content: oversizedLine, language: "swift")

        view.document = document
        await view.visibleHighlightBudgetTask?.value

        #expect(document.syntaxController?.currentSnapshot().line(0)?.status == .intentionallyLimited)
    }

    private func renderedCells(from buffer: EditorCellBuffer) -> [EditorCellGPU] {
        buffer.syncToGPU()
        let count = buffer.cellCount
        guard count > 0 else { return [] }
        let pointer = buffer.currentBuffer.contents().bindMemory(
            to: EditorCellGPU.self,
            capacity: count
        )
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}
