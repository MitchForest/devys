import Metal
import Testing
@testable import GhosttyTerminal
import GhosttyTerminalCore

@Suite("Ghostty Terminal Renderer Tests")
struct GhosttyTerminalRendererTests {
    @Test("Metal host views use explicit on-demand draw configuration")
    func metalViewConfigurationIsOnDemand() {
        let configuration = GhosttyTerminalMetalViewConfiguration.onDemand

        #expect(configuration.isPaused)
        #expect(configuration.enableSetNeedsDisplay)
        #expect(configuration.preferredFramesPerSecond == 60)
        #expect(configuration.framebufferOnly)
    }

    @Test("Renderer resources reuse pipelines per device and atlas state per font and scale")
    @MainActor
    func rendererResourcesReusePipelineAndAtlasByKey() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let fontMetrics = GhosttyTerminalFontMetrics.default()

        let first = try GhosttyTerminalRendererSharedResources.shared(
            device: device,
            fontMetrics: fontMetrics,
            scaleFactor: 2
        )
        let second = try GhosttyTerminalRendererSharedResources.shared(
            device: device,
            fontMetrics: fontMetrics,
            scaleFactor: 2
        )
        let scaled = try GhosttyTerminalRendererSharedResources.shared(
            device: device,
            fontMetrics: fontMetrics,
            scaleFactor: 3
        )

        #expect(first === second)
        #expect(first.pipeline === second.pipeline)
        #expect(first.atlas === second.atlas)
        #expect(first !== scaled)
        #expect(first.pipeline === scaled.pipeline)
        #expect(first.atlas !== scaled.atlas)
    }

    @Test("Renderer warmup can precreate shared Metal resources")
    @MainActor
    func rendererWarmupPreparesResources() throws {
        let warmed = try GhosttyTerminalRendererWarmup.prepareSharedResources(scaleFactor: 2)

        if warmed {
            guard let device = MTLCreateSystemDefaultDevice() else {
                Issue.record("Warmup reported success without a Metal device.")
                return
            }

            let resources = try GhosttyTerminalRendererSharedResources.shared(
                device: device,
                fontMetrics: GhosttyTerminalFontMetrics.default(),
                scaleFactor: 2
            )
            let pipeline = try GhosttyTerminalPipelineCache.sharedPipeline(device: device)
            #expect(resources.pipeline === pipeline)
        } else {
            #expect(MTLCreateSystemDefaultDevice() == nil)
        }
    }

    @Test("Block cursor uses cell-aware colors instead of an overlay tint")
    func blockCursorColorsPreserveReadableGlyphContrast() {
        let cell = GhosttyTerminalProjectedCell(
            column: 3,
            grapheme: "x",
            foregroundPacked: 0x202020,
            backgroundPacked: 0xFFFFFF
        )
        let surfaceState = GhosttyTerminalSurfaceState(
            cols: 8,
            rows: 1,
            cursor: GhosttyTerminalCursor(row: 0, col: 3),
            cursorVisible: true,
            cursorStyle: .block,
            cursorColorPacked: 0x202020
        )
        let colors = blockCursorPackedColors(
            for: cell,
            surfaceState: surfaceState,
            appearance: .defaultDark
        )

        #expect(colors.backgroundPacked == 0x202020)
        #expect(colors.foregroundPacked == 0xFFFFFF)
    }

    @Test("Block cursor resolves wide-tail positions back to the head cell")
    func blockCursorResolvesWideTailToRenderableCell() {
        let row = GhosttyTerminalProjectedRow(
            index: 0,
            cells: [
                GhosttyTerminalProjectedCell(
                    column: 0,
                    grapheme: "界",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000,
                    isWide: true
                ),
                GhosttyTerminalProjectedCell(
                    column: 1,
                    grapheme: "",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000,
                    isWideContinuation: true
                ),
            ],
            isDirty: true
        )
        let surfaceState = GhosttyTerminalSurfaceState(
            cols: 2,
            rows: 1,
            cursor: GhosttyTerminalCursor(row: 0, col: 1),
            cursorVisible: true,
            cursorStyle: .block,
            cursorWideTail: true
        )

        let resolved = resolvedBlockCursorCell(in: row, surfaceState: surfaceState)

        #expect(resolved?.column == 0)
        #expect(resolved?.isWide == true)
    }

    @Test("Block cursor never paints an overlay beyond the visible grid")
    func blockCursorDoesNotClampPastVisibleColumns() {
        let grid = GhosttyTerminalGridMetrics(
            cols: 4,
            rows: 1,
            cellWidth: 8,
            cellHeight: 16
        )
        let surfaceState = GhosttyTerminalSurfaceState(
            cols: 4,
            rows: 1,
            cursor: GhosttyTerminalCursor(row: 0, col: 4),
            cursorVisible: true,
            cursorStyle: .block
        )

        #expect(grid.overlayCursorRect(for: surfaceState) == nil)
    }

    @Test("Block cursor movement invalidates the old and new cursor rows")
    func blockCursorMovementInvalidatesAffectedRows() {
        let previous = GhosttyBlockCursorPresentation(
            row: 0,
            col: 1,
            colorPacked: nil,
            wideTail: false,
            pendingWrap: false
        )
        let current = GhosttyBlockCursorPresentation(
            row: 1,
            col: 3,
            colorPacked: nil,
            wideTail: false,
            pendingWrap: false
        )

        let dirtyRows = blockCursorRowsNeedingRebuild(
            previous: previous,
            current: current
        )

        #expect(dirtyRows == Set([0, 1]))
    }

    @Test("Block cursor presentation clamps a pending-wrap cursor back into the visible row")
    func blockCursorPresentationClampsPendingWrap() {
        let surfaceState = GhosttyTerminalSurfaceState(
            cols: 4,
            rows: 1,
            cursor: GhosttyTerminalCursor(row: 0, col: 4),
            cursorVisible: true,
            cursorStyle: .block,
            cursorPendingWrap: true
        )

        let presentation = blockCursorPresentation(
            for: surfaceState,
            cols: 4,
            rows: 1
        )

        #expect(presentation?.row == 0)
        #expect(presentation?.col == 3)
    }

    @Test("Block cursor resolves only on the actual cursor row")
    func blockCursorDoesNotResolveOnRowsAboveCursor() {
        let rowAbove = GhosttyTerminalProjectedRow(
            index: 0,
            cells: [
                GhosttyTerminalProjectedCell(
                    column: 0,
                    grapheme: " ",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
                GhosttyTerminalProjectedCell(
                    column: 1,
                    grapheme: "a",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
                GhosttyTerminalProjectedCell(
                    column: 2,
                    grapheme: " ",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
                GhosttyTerminalProjectedCell(
                    column: 3,
                    grapheme: " ",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
            ],
            isDirty: true
        )
        let cursorRow = GhosttyTerminalProjectedRow(
            index: 2,
            cells: [
                GhosttyTerminalProjectedCell(
                    column: 0,
                    grapheme: " ",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
                GhosttyTerminalProjectedCell(
                    column: 1,
                    grapheme: "b",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
                GhosttyTerminalProjectedCell(
                    column: 2,
                    grapheme: " ",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
                GhosttyTerminalProjectedCell(
                    column: 3,
                    grapheme: " ",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                ),
            ],
            isDirty: true
        )
        let surfaceState = GhosttyTerminalSurfaceState(
            cols: 4,
            rows: 3,
            cursor: GhosttyTerminalCursor(row: 2, col: 1),
            cursorVisible: true,
            cursorStyle: .block
        )

        #expect(resolvedBlockCursorCell(in: rowAbove, surfaceState: surfaceState) == nil)
        #expect(resolvedBlockCursorCell(in: cursorRow, surfaceState: surfaceState)?.column == 1)
    }

    @Test("Merged rows tolerate overlapping cursor and visible row indexes")
    func mergedRowsDeduplicateOverlappingIndexes() {
        let overlapping = GhosttyTerminalProjectedRow(
            index: 1,
            cells: [
                GhosttyTerminalProjectedCell(
                    column: 0,
                    grapheme: "x",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                )
            ],
            isDirty: true
        )
        let extra = GhosttyTerminalProjectedRow(
            index: 3,
            cells: [
                GhosttyTerminalProjectedCell(
                    column: 0,
                    grapheme: "y",
                    foregroundPacked: 0xFFFFFF,
                    backgroundPacked: 0x000000
                )
            ],
            isDirty: true
        )

        let merged = mergedRows([overlapping], [overlapping, extra])

        #expect(merged.map(\.index) == [1, 3])
    }
}
