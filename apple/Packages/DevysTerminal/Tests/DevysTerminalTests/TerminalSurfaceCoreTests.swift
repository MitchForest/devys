// Ported from the reference repo's TerminalSurfaceTests (P0-014), split
// into nested suites under one serialized parent: the shared
// MetalSurfaceDiagnostics counters must never interleave across suites.
// Runtime lifecycle/interaction suites live in
// TerminalSurfaceRuntimeTests.swift under the same parent.

import CoreGraphics
import Foundation
import TerminalCore
@testable import TerminalSurfaceCore
import TerminalVT
import Testing

@Suite(.serialized)
struct TerminalSurfaceCoreTests {}

extension TerminalSurfaceCoreTests {
    @Suite
    struct Statics {
        @Test
        @MainActor
        func terminalSurfaceCallbacksAreConstructible() {
            let callbacks = TerminalSurfaceCallbacks()

            callbacks.statusChanged(.running)
            #expect(TerminalStatus.running == .running)
        }

        @Test
        @MainActor
        func terminalSurfaceUsesFastResizeCadence() {
            #expect(TerminalSurfaceTiming.viewportResizeCoalescingNanoseconds == 8_000_000)
            #expect(TerminalSurfaceTiming.renderInvalidationCoalescingNanoseconds == 8_000_000)
            #expect(TerminalSurfaceTiming.scrollProcessingCoalescingNanoseconds == 8_000_000)
            #expect(TerminalSurfaceTiming.drawRetryNanoseconds == 8_000_000)
        }

        @Test
        func terminalSurfaceUsesCompactDefaultFontSize() {
            #expect(TerminalSurfaceDefaults.fontSize == 13)
            #expect(TerminalSurfaceDefaults.contentPadding == 2)
        }

        @Test
        func terminalAppearanceResolverCreatesReadableLightAndDarkAppearances() {
            // Host-theme primitives with a deliberately low-contrast
            // requested foreground: the resolver must clamp it to a
            // readable color.
            let light = TerminalSurfaceAppearanceResolver.appearance(
                colorScheme: .light,
                background: TerminalColor(red: 250, green: 250, blue: 249),
                foreground: TerminalColor(red: 200, green: 200, blue: 200)
            )
            let dark = TerminalSurfaceAppearanceResolver.appearance(
                colorScheme: .dark,
                background: TerminalColor(red: 24, green: 24, blue: 27),
                foreground: TerminalColor(red: 60, green: 60, blue: 64)
            )

            #expect(light.colorScheme == .light)
            #expect(dark.colorScheme == .dark)
            #expect(light.background == TerminalColor(red: 250, green: 250, blue: 249))
            #expect(dark.background == TerminalColor(red: 24, green: 24, blue: 27))
            #expect(light.backgroundOpacity == 0)
            #expect(dark.backgroundOpacity == 0)
            #expect(light.palette.count == 16)
            #expect(dark.palette.count == 16)
            #expect(light.foreground.contrastRatio(with: light.background) >= 7)
            #expect(dark.foreground.contrastRatio(with: dark.background) >= 7)
            #expect(light.cursorColor.contrastRatio(with: light.background) >= 7)
            #expect(dark.cursorColor.contrastRatio(with: dark.background) >= 7)
            #expect(light.selectionBackground.contrastRatio(with: light.background) > 1.1)
            #expect(dark.selectionBackground.contrastRatio(with: dark.background) > 1.1)
        }

        @Test
        func terminalAppearanceResolverKeepsAlreadyReadableForegrounds() {
            let appearance = TerminalSurfaceAppearanceResolver.appearance(
                colorScheme: .light,
                background: .white,
                foreground: .black
            )

            #expect(appearance.foreground == .black)
            #expect(appearance.cursorColor == .black)
        }

        @Test
        @MainActor
        func terminalSurfaceDiagnosticsRecordResizeAndDrawSignals() {
            MetalSurfaceDiagnostics.reset()

            MetalSurfaceDiagnostics.recordHostCreated(surface: "terminal")
            MetalSurfaceDiagnostics.recordHostFrameChanged(surface: "terminal")
            MetalSurfaceDiagnostics.recordDrawableSizeChanged(surface: "terminal")
            MetalSurfaceDiagnostics.recordViewportRequested(surface: "terminal")
            MetalSurfaceDiagnostics.recordViewportApplied(surface: "terminal")
            MetalSurfaceDiagnostics.recordResizeIncrementsApplied(surface: "terminal")
            MetalSurfaceDiagnostics.recordRenderInvalidationRequested(surface: "terminal")
            MetalSurfaceDiagnostics.recordRenderInvalidationApplied(surface: "terminal")
            MetalSurfaceDiagnostics.recordRenderSnapshotApplied(surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollEventReceived(surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollLinesEmitted(3, surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollTaskStarted(surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollApplication(-3, surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollRoutedToViewport(surface: "terminal")
            MetalSurfaceDiagnostics.recordScrollRoutedToPTY(surface: "terminal")
            MetalSurfaceDiagnostics.recordDrawRequested(surface: "terminal")
            MetalSurfaceDiagnostics.recordDrawCoalesced(surface: "terminal")
            MetalSurfaceDiagnostics.recordDrawImmediate(surface: "terminal")

            let snapshot = MetalSurfaceDiagnostics.snapshot
            #expect(snapshot.hostCreated == 1)
            #expect(snapshot.hostFrameChanges == 1)
            #expect(snapshot.drawableSizeChanges == 1)
            #expect(snapshot.viewportRequests == 1)
            #expect(snapshot.viewportApplications == 1)
            #expect(snapshot.resizeIncrementsApplied == 1)
            #expect(snapshot.renderInvalidationsRequested == 1)
            #expect(snapshot.renderInvalidationsApplied == 1)
            #expect(snapshot.renderSnapshotsApplied == 1)
            #expect(snapshot.scrollEventsReceived == 1)
            #expect(snapshot.scrollLinesEmitted == 3)
            #expect(snapshot.scrollTasksStarted == 1)
            #expect(snapshot.scrollApplications == 1)
            #expect(snapshot.scrollDeltasApplied == 3)
            #expect(snapshot.scrollRoutedToViewport == 1)
            #expect(snapshot.scrollRoutedToPTY == 1)
            #expect(snapshot.drawRequested == 1)
            #expect(snapshot.coalescedDraws == 1)
            #expect(snapshot.immediateDraws == 1)
        }

        @Test
        func terminalScrollAccumulatorPreservesFractionalDeltas() {
            var accumulator = TerminalScrollAccumulator()

            #expect(accumulator.appendPixelDelta(4, lineHeight: 10) == 0)
            #expect(accumulator.appendPixelDelta(4, lineHeight: 10) == 0)
            #expect(accumulator.appendPixelDelta(4, lineHeight: 10) == 1)
            #expect(accumulator.appendPixelDelta(-6, lineHeight: 10) == 0)
            #expect(accumulator.appendPixelDelta(-6, lineHeight: 10) == -1)

            accumulator.reset()

            #expect(accumulator.appendPixelDelta(9, lineHeight: 10) == 0)
        }

        @Test
        func terminalSurfacePixelSizeDerivesGridFromBackingPixels() {
            let pixelSize = TerminalSurfacePixelSize(
                pixelWidth: 1604,
                pixelHeight: 820,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            )

            #expect(pixelSize.cellWidthPx == 16)
            #expect(pixelSize.cellHeightPx == 40)
            #expect(pixelSize.viewportSize.cols == 100)
            #expect(pixelSize.viewportSize.rows == 20)
        }

        @Test
        func terminalSurfacePixelSizeClampsToMinimumGrid() {
            let pixelSize = TerminalSurfacePixelSize(
                pixelWidth: 10,
                pixelHeight: 10,
                scale: 1,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            )

            #expect(pixelSize.viewportSize.cols == 20)
            #expect(pixelSize.viewportSize.rows == 5)
        }

        @Test
        func resizeCoordinatorSeparatesVTAndPTYResizeWork() throws {
            let initial = TerminalSurfaceResizeTransaction(pixelSize: TerminalSurfacePixelSize(
                pixelWidth: 1600,
                pixelHeight: 800,
                scale: 2,
                cellWidthPoints: 8,
                cellHeightPoints: 20
            ))
            let sameGridDifferentCells = TerminalSurfaceResizeTransaction(pixelSize: TerminalSurfacePixelSize(
                pixelWidth: 2000,
                pixelHeight: 1000,
                scale: 2,
                cellWidthPoints: 10,
                cellHeightPoints: 25
            ))
            let changedGrid = TerminalSurfaceResizeTransaction(pixelSize: TerminalSurfacePixelSize(
                pixelWidth: 2400,
                pixelHeight: 1000,
                scale: 2,
                cellWidthPoints: 10,
                cellHeightPoints: 25
            ))

            var coordinator = TerminalSurfaceResizeCoordinator()

            let observedInitial = coordinator.observe(initial)
            let observedDuplicateInitial = coordinator.observe(initial)
            let pendingInitialCandidate = coordinator.takePendingTransaction()
            let pendingInitial = try #require(pendingInitialCandidate)
            #expect(observedInitial)
            #expect(observedDuplicateInitial == false)
            #expect(pendingInitial == initial)
            coordinator.markInitialPTYSizeApplied(initial.size)

            let initialApplication = coordinator.application(for: initial)
            #expect(initialApplication.shouldResizeVT)
            #expect(initialApplication.shouldResizePTY == false)
            coordinator.markApplied(initialApplication, ptyResizeSucceeded: false)

            let observedSameGrid = coordinator.observe(sameGridDifferentCells)
            let sameGridTransactionCandidate = coordinator.takePendingTransaction()
            let sameGridTransaction = try #require(sameGridTransactionCandidate)
            #expect(observedSameGrid)
            let vtOnlyApplication = coordinator.application(for: sameGridTransaction)
            #expect(vtOnlyApplication.shouldResizeVT)
            #expect(vtOnlyApplication.shouldResizePTY == false)
            coordinator.markApplied(vtOnlyApplication, ptyResizeSucceeded: false)

            let observedChangedGrid = coordinator.observe(changedGrid)
            let changedGridTransactionCandidate = coordinator.takePendingTransaction()
            let changedGridTransaction = try #require(changedGridTransactionCandidate)
            #expect(observedChangedGrid)
            let fullApplication = coordinator.application(for: changedGridTransaction)
            #expect(fullApplication.shouldResizeVT)
            #expect(fullApplication.shouldResizePTY)
        }
    }
}

extension TerminalSurfaceCoreTests {
    @Suite
    struct Sessions {
        // P0-045: the pinch-to-resize path re-enters the VT through the
        // same cell-size → resize flow; a scrolled-back viewport must
        // survive the font change instead of snapping to the bottom.
        @Test
        @MainActor
        func viewportOffsetSurvivesCellSizeResize() async throws {
            let vt = try TerminalVTRuntime(cols: 40, rows: 5)
            var transcript = ""
            for line in 1...30 {
                transcript += "line \(line)\r\n"
            }
            _ = await vt.write(Data(transcript.utf8))

            let scrolled = await vt.scrollViewport(by: -10)
            #expect(scrolled.surfaceState.viewportOffset == 10)

            // A pinch from 13pt to 16pt shrinks the grid and grows the
            // cell pixels; the engine keeps the scrollback position.
            let resized = await vt.resize(cols: 34, rows: 5, cellWidthPx: 20, cellHeightPx: 38)

            #expect(resized.surfaceState.viewportOffset > 0)
        }

        @Test
        @MainActor
        func renderSessionSelectionTextStaysOnDemand() {
            let projection = makeTerminalProjection(strings: ["hello"])
            let session = TerminalSurfaceRenderSession(
                surfaceState: .init(cols: 5, rows: 1),
                frameProjection: projection
            )

            session.applySelection(TerminalSelectionRange(
                start: TerminalSelectionPoint(row: 0, col: 1),
                end: TerminalSelectionPoint(row: 0, col: 3)
            ))

            #expect(session.selectionText() == "ell")
        }

        @Test
        @MainActor
        func projectionTextNormalizesReversedMultilineSelection() {
            let projection = makeTerminalProjection(strings: [
                "one   ",
                "two   "
            ])
            let selection = TerminalSelectionRange(
                start: TerminalSelectionPoint(row: 1, col: 2),
                end: TerminalSelectionPoint(row: 0, col: 1)
            )

            #expect(projection.text(in: selection) == "ne\ntwo")
        }

        @Test
        @MainActor
        func projectionTextSkipsWideContinuationCells() {
            let row = TerminalProjectedRow(
                index: 0,
                cells: [
                    makeTerminalCell(column: 0, grapheme: "a"),
                    makeTerminalCell(column: 1, grapheme: "界", isWide: true),
                    makeTerminalCell(column: 2, grapheme: "", isWideContinuation: true),
                    makeTerminalCell(column: 3, grapheme: "b")
                ],
                isDirty: true
            )
            let projection = makeTerminalProjection(rows: [row], cols: 4)
            let selection = TerminalSelectionRange(
                start: TerminalSelectionPoint(row: 0, col: 0),
                end: TerminalSelectionPoint(row: 0, col: 3)
            )

            #expect(projection.text(in: selection) == "a界b")
        }

        @Test
        @MainActor
        func projectionWordSelectionUsesRenderableWideCellHead() throws {
            let row = TerminalProjectedRow(
                index: 0,
                cells: [
                    makeTerminalCell(column: 0, grapheme: "a"),
                    makeTerminalCell(column: 1, grapheme: "界", isWide: true),
                    makeTerminalCell(column: 2, grapheme: "", isWideContinuation: true),
                    makeTerminalCell(column: 3, grapheme: " "),
                    makeTerminalCell(column: 4, grapheme: "b")
                ],
                isDirty: true
            )
            let projection = makeTerminalProjection(rows: [row], cols: 5)
            let selection = try #require(projection.wordSelection(atRow: 0, col: 2))

            #expect(selection == TerminalSelectionRange(
                start: TerminalSelectionPoint(row: 0, col: 0),
                end: TerminalSelectionPoint(row: 0, col: 1)
            ))
            #expect(projection.text(in: selection) == "a界")
        }

        @Test
        @MainActor
        func renderSessionCoalescesOutputInvalidations() async throws {
            MetalSurfaceDiagnostics.reset()
            let session = TerminalSurfaceRenderSession(
                surfaceState: .init(cols: 5, rows: 1),
                frameProjection: .empty(cols: 5, rows: 1)
            )
            var invalidations = 0
            session.invalidationHandler = {
                invalidations += 1
            }
            let update = TerminalSurfaceUpdate(
                surfaceState: .init(cols: 5, rows: 1),
                frameProjection: .empty(cols: 5, rows: 1)
            )

            session.apply(update: update)
            session.apply(update: update)
            session.apply(update: update)

            #expect(session.renderRevision == 3)
            #expect(invalidations == 0)
            #expect(MetalSurfaceDiagnostics.snapshot.renderInvalidationsRequested == 3)

            try await terminalTestWait { invalidations == 1 }

            #expect(invalidations == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.renderInvalidationsApplied == 1)
        }

        @Test
        @MainActor
        func renderSessionSelectionInvalidatesImmediately() {
            MetalSurfaceDiagnostics.reset()
            let session = TerminalSurfaceRenderSession(
                surfaceState: .init(cols: 5, rows: 1),
                frameProjection: .empty(cols: 5, rows: 1)
            )
            var invalidations = 0
            session.invalidationHandler = {
                invalidations += 1
            }

            session.applySelection(TerminalSelectionRange(
                start: TerminalSelectionPoint(row: 0, col: 1),
                end: TerminalSelectionPoint(row: 0, col: 3)
            ))

            #expect(session.renderRevision == 1)
            #expect(invalidations == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.renderInvalidationsRequested == 0)
            #expect(MetalSurfaceDiagnostics.snapshot.renderInvalidationsApplied == 1)
        }

        @Test
        @MainActor
        func metalDrawSchedulerCoalescesDrawRequests() async throws {
            MetalSurfaceDiagnostics.reset()
            let scheduler = MetalDrawScheduler(surface: "terminal")

            scheduler.requestDraw()
            scheduler.requestDraw()
            scheduler.requestDraw()

            #expect(MetalSurfaceDiagnostics.snapshot.drawRequested == 3)
            #expect(MetalSurfaceDiagnostics.snapshot.coalescedDraws == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.immediateDraws == 0)

            try await terminalTestWait { MetalSurfaceDiagnostics.snapshot.drawSkipped == 1 }

            #expect(MetalSurfaceDiagnostics.snapshot.drawSkipped == 1)
            #expect(MetalSurfaceDiagnostics.snapshot.immediateDraws == 0)
        }
    }
}

extension TerminalSurfaceCoreTests {
    @Suite
    struct TextRanges {
        @Test
        func terminalTextRangeProjectionClipsVisibleRows() {
            let range = TerminalTextRange(
                start: TerminalTextPosition(row: 3, column: 0),
                end: TerminalTextPosition(row: 6, column: 8),
                snapshotRevision: 12
            )
            let snapshot = TerminalTextRangeProjectionResolver.snapshot(
                for: [range],
                surfaceState: .init(cols: 80, rows: 4, viewportOffset: 2, scrollbackRows: 6),
                snapshotRevision: 18,
                pixelSize: TerminalSurfacePixelSize(
                    pixelWidth: 800,
                    pixelHeight: 200,
                    scale: 2,
                    cellWidthPoints: 8,
                    cellHeightPoints: 10
                ),
                contentPadding: 2
            )

            #expect(snapshot.unavailableReason == nil)
            #expect(snapshot.snapshotRevision == 18)
            #expect(snapshot.projections == [
                TerminalTextRangeProjection(
                    range: range,
                    visibleStartRow: 0,
                    visibleEndRow: 2,
                    topY: 2,
                    height: 30
                )
            ])
        }

        @Test
        func terminalTextRangeProjectionOmitsOffscreenRanges() {
            let snapshot = TerminalTextRangeProjectionResolver.snapshot(
                for: [
                    TerminalTextRange(
                        start: TerminalTextPosition(row: 0, column: 0),
                        end: TerminalTextPosition(row: 0, column: 4),
                        snapshotRevision: 1
                    )
                ],
                surfaceState: .init(cols: 80, rows: 4, viewportOffset: 0, scrollbackRows: 8),
                snapshotRevision: 2,
                pixelSize: TerminalSurfacePixelSize(
                    pixelWidth: 800,
                    pixelHeight: 200,
                    scale: 2,
                    cellWidthPoints: 8,
                    cellHeightPoints: 10
                ),
                contentPadding: 2
            )

            #expect(snapshot.unavailableReason == nil)
            #expect(snapshot.projections.isEmpty)
        }

        @Test
        func terminalTextRangeProjectionReportsUnavailableStates() {
            let range = TerminalTextRange(
                start: TerminalTextPosition(row: 1, column: 0),
                end: TerminalTextPosition(row: 1, column: 4),
                snapshotRevision: 1
            )
            let runtimeNotReady = TerminalTextRangeProjectionResolver.snapshot(
                for: [range],
                surfaceState: .init(cols: 80, rows: 4),
                snapshotRevision: 2,
                pixelSize: nil,
                contentPadding: 2
            )
            let altScreen = TerminalTextRangeProjectionResolver.snapshot(
                for: [range],
                surfaceState: .init(cols: 80, rows: 4, altScreenMode: true),
                snapshotRevision: 2,
                pixelSize: TerminalSurfacePixelSize(
                    pixelWidth: 800,
                    pixelHeight: 200,
                    scale: 2,
                    cellWidthPoints: 8,
                    cellHeightPoints: 10
                ),
                contentPadding: 2
            )

            #expect(runtimeNotReady.unavailableReason == .runtimeNotReady)
            #expect(altScreen.unavailableReason == .alternateScreen)
        }

        @Test
        func textRangeMatcherFindsNewestSingleLineMatch() {
            let result = TerminalTextRangeMatcher.latestRange(
                matching: TerminalTextQuery(text: "target"),
                in: [
                    GhosttyTerminalScreenLine(row: 0, text: "target first"),
                    GhosttyTerminalScreenLine(row: 1, text: "other"),
                    GhosttyTerminalScreenLine(row: 2, text: "latest target")
                ],
                snapshotRevision: 7
            )

            #expect(result == .found(TerminalTextRange(
                start: TerminalTextPosition(row: 2, column: 7),
                end: TerminalTextPosition(row: 2, column: 12),
                snapshotRevision: 7
            )))
        }

        @Test
        func textRangeMatcherFindsNewestExactMultilineMatch() {
            let result = TerminalTextRangeMatcher.latestRange(
                matching: TerminalTextQuery(text: "one\ntwo"),
                in: [
                    GhosttyTerminalScreenLine(row: 0, text: "one"),
                    GhosttyTerminalScreenLine(row: 1, text: "two"),
                    GhosttyTerminalScreenLine(row: 2, text: "one"),
                    GhosttyTerminalScreenLine(row: 3, text: "two")
                ],
                snapshotRevision: 8
            )

            #expect(result == .found(TerminalTextRange(
                start: TerminalTextPosition(row: 2, column: 0),
                end: TerminalTextPosition(row: 3, column: 2),
                snapshotRevision: 8
            )))
        }

        @Test
        func textRangeMatcherFallsBackToFirstNonEmptyLine() {
            let result = TerminalTextRangeMatcher.latestRange(
                matching: TerminalTextQuery(text: "\nhello\nmissing"),
                in: [
                    GhosttyTerminalScreenLine(row: 0, text: "prompt: hello")
                ],
                snapshotRevision: 9
            )

            #expect(result == .found(TerminalTextRange(
                start: TerminalTextPosition(row: 0, column: 8),
                end: TerminalTextPosition(row: 0, column: 12),
                snapshotRevision: 9
            )))
        }

        @Test
        func textRangeMatcherHonorsRowLimit() {
            let result = TerminalTextRangeMatcher.latestRange(
                matching: TerminalTextQuery(text: "target", searchLimitRows: 2),
                in: [
                    GhosttyTerminalScreenLine(row: 0, text: "target"),
                    GhosttyTerminalScreenLine(row: 1, text: "other"),
                    GhosttyTerminalScreenLine(row: 2, text: "also other")
                ],
                snapshotRevision: 10
            )

            #expect(result == .notFound)
        }
    }
}
