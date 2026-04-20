import Foundation
import Testing
import GhosttyTerminalCore

@Suite("Ghostty Terminal Projection Tests")
struct GhosttyTerminalProjectionTests {
    @Test("Projection cells can carry combining-mark graphemes intact")
    func combiningMarksStayInSingleProjectedCell() {
        let projection = GhosttyTerminalFrameProjection(
            cols: 2,
            rows: 1,
            defaultForegroundPacked: 0xFFFFFF,
            defaultBackgroundPacked: 0x000000,
            dirtyState: GhosttyTerminalDirtyState(kind: .full, dirtyRows: [0]),
            rowsByIndex: [
                GhosttyTerminalProjectedRow(
                    index: 0,
                    cells: [
                        GhosttyTerminalProjectedCell(column: 0, grapheme: "e\u{301}", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 1, grapheme: " ", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                    ],
                    isDirty: true
                ),
            ],
            overlay: GhosttyTerminalOverlayProjection(
                selectionRange: nil,
                cursor: .init(),
                cursorVisible: false,
                cursorStyle: .block,
                viewportOffset: 0
            )
        )

        #expect(projection.row(at: 0)?.cells[0].grapheme == "e\u{301}")
    }

    @Test("Projection marks wide glyphs and continuation cells")
    func wideGlyphsExposeContinuationCells() async throws {
        let runtime = try GhosttyVTRuntime(cols: 40, rows: 8)
        let result = await runtime.write(Data("界".utf8))
        let row = try #require(result.surfaceUpdate.frameProjection.row(at: 0))
        #expect(row.cells[0].isWide)
        #expect(row.cells[0].grapheme == "界")
        #expect(row.cells[1].isWideContinuation)
    }

    @Test("Runtime projection includes default colors and cursor metadata")
    func runtimeProjectionIncludesDefaultColorsAndCursorMetadata() async throws {
        let runtime = try GhosttyVTRuntime(cols: 40, rows: 8)
        let result = await runtime.write(Data("abc".utf8))

        #expect(result.surfaceUpdate.frameProjection.defaultForegroundPacked == 0xFFFFFF)
        #expect(result.surfaceUpdate.frameProjection.defaultBackgroundPacked == 0x282C34)
        #expect(result.surfaceUpdate.surfaceState.cursor.row == 0)
        #expect(result.surfaceUpdate.surfaceState.cursor.col == 3)
        #expect(result.surfaceUpdate.surfaceState.cursorVisible)
        #expect(result.surfaceUpdate.surfaceState.cursorStyle == .block)
        #expect(result.surfaceUpdate.surfaceState.cursorColorPacked == 0xFFFFFF)
        #expect(result.surfaceUpdate.surfaceState.cursorWideTail == false)
        #expect(result.surfaceUpdate.surfaceState.cursorPendingWrap == false)
    }

    @Test("Updating appearance changes defaults, preserves truecolor, and updates ANSI colors")
    func runtimeAppearanceUpdatesFollowTheExplicitThemeContract() async throws {
        let darkAppearance = GhosttyTerminalAppearance(
            colorScheme: .dark,
            background: GhosttyTerminalColor(hex: "#1C1B19"),
            foreground: GhosttyTerminalColor(hex: "#EDEDEB"),
            cursorColor: GhosttyTerminalColor(hex: "#EDEDEB"),
            selectionBackground: GhosttyTerminalColor(hex: "#222120"),
            palette: GhosttyTerminalAppearance.ghosttyDarkPalette
        )
        let lightAppearance = GhosttyTerminalAppearance(
            colorScheme: .light,
            background: GhosttyTerminalColor(hex: "#FFFFFF"),
            foreground: GhosttyTerminalColor(hex: "#1C1B19"),
            cursorColor: GhosttyTerminalColor(hex: "#1C1B19"),
            selectionBackground: GhosttyTerminalColor(hex: "#E4E1DC"),
            palette: GhosttyTerminalAppearance.ghosttyLightPalette
        )
        let runtime = try GhosttyVTRuntime(cols: 40, rows: 8, appearance: darkAppearance)

        let initial = await runtime.write(
            Data("a\u{1B}[31mb\u{1B}[38;2;1;2;3mc\u{1B}[39m\u{1B}[0m".utf8)
        )
        let initialRow = try #require(initial.surfaceUpdate.frameProjection.row(at: 0))
        let ansiForeground = initialRow.cells[1].foregroundPacked
        let truecolorForeground = initialRow.cells[2].foregroundPacked

        #expect(initial.surfaceUpdate.frameProjection.defaultForegroundPacked == darkAppearance.foreground.packedRGB)
        #expect(initial.surfaceUpdate.frameProjection.defaultBackgroundPacked == darkAppearance.background.packedRGB)
        #expect(initialRow.cells[0].foregroundPacked == darkAppearance.foreground.packedRGB)
        #expect(ansiForeground == GhosttyTerminalAppearance.ghosttyDarkPalette[1].packedRGB)
        #expect(truecolorForeground == 0x010203)

        let updated = await runtime.updateAppearance(lightAppearance)
        let updatedRow = try #require(updated.frameProjection.row(at: 0))

        #expect(updated.frameProjection.defaultForegroundPacked == lightAppearance.foreground.packedRGB)
        #expect(updated.frameProjection.defaultBackgroundPacked == lightAppearance.background.packedRGB)
        #expect(updatedRow.cells[0].foregroundPacked == lightAppearance.foreground.packedRGB)
        #expect(updatedRow.cells[1].foregroundPacked == GhosttyTerminalAppearance.ghosttyLightPalette[1].packedRGB)
        #expect(updatedRow.cells[2].foregroundPacked == truecolorForeground)
    }

    @Test("Runtime projection includes terminal mode metadata")
    func runtimeProjectionIncludesTerminalModes() async throws {
        let runtime = try GhosttyVTRuntime(cols: 40, rows: 8)
        let result = await runtime.write(Data("\u{1B}[?1h\u{1B}[?2004h".utf8))

        #expect(result.surfaceUpdate.surfaceState.appCursorMode)
        #expect(result.surfaceUpdate.surfaceState.bracketedPasteMode)
    }

    @Test("Projection preserves reverse-video cells for TUI-managed carets")
    func projectionPreservesInverseCellColors() async throws {
        let runtime = try GhosttyVTRuntime(cols: 8, rows: 2)
        let result = await runtime.write(Data("\u{1B}[7m \u{1B}[27m".utf8))
        let row = try #require(result.surfaceUpdate.frameProjection.row(at: 0))
        let cell = row.cells[0]

        #expect(cell.grapheme == " ")
        #expect(cell.foregroundPacked == result.surfaceUpdate.frameProjection.defaultBackgroundPacked)
        #expect(cell.backgroundPacked == result.surfaceUpdate.frameProjection.defaultForegroundPacked)
    }

    @Test("Runtime projection includes scrollback and viewport metadata")
    func runtimeProjectionIncludesScrollbackAndViewportMetadata() async throws {
        let runtime = try GhosttyVTRuntime(cols: 20, rows: 2)
        _ = await runtime.write(Data("one\r\ntwo\r\nthree".utf8))

        let bottom = await runtime.write(Data())
        #expect(bottom.surfaceUpdate.surfaceState.scrollbackRows > 0)
        #expect(bottom.surfaceUpdate.surfaceState.viewportOffset == 0)

        let scrolled = await runtime.scrollViewport(by: -1)
        #expect(scrolled.surfaceState.viewportOffset > 0)
    }

    @Test("Projection preserves dirty updates and clean no-op frames")
    func projectionTracksDirtyAndCleanFrames() async throws {
        let runtime = try GhosttyVTRuntime(cols: 20, rows: 4)

        let initial = await runtime.write(Data("hello".utf8))
        #expect(initial.surfaceUpdate.frameProjection.dirtyState.kind == .full)
        #expect(initial.surfaceUpdate.frameProjection.rowsByIndex.isEmpty == false)

        let update = await runtime.write(Data("!".utf8))
        #expect(update.surfaceUpdate.frameProjection.dirtyState.kind != .clean)
        #expect(update.surfaceUpdate.frameProjection.row(at: 0) != nil)

        let clean = await runtime.write(Data())
        #expect(clean.surfaceUpdate.frameProjection.dirtyState.kind == .clean)
        #expect(clean.surfaceUpdate.frameProjection.rowsByIndex.isEmpty)
    }

    @Test("Projection reports exact partial dirty rows from render state")
    func projectionReportsExactPartialDirtyRows() async throws {
        let runtime = try GhosttyVTRuntime(cols: 20, rows: 4)

        _ = await runtime.write(Data("alpha\r\nbeta\r\ngamma".utf8))
        _ = await runtime.write(Data())

        let update = await runtime.write(Data("\u{1B}[2;1HZ".utf8))

        #expect(update.surfaceUpdate.frameProjection.dirtyState.kind == .partial)
        #expect(update.surfaceUpdate.frameProjection.dirtyState.dirtyRows == [1, 2])
        #expect(update.surfaceUpdate.frameProjection.rowsByIndex.map(\.index) == [1, 2])
        #expect(update.surfaceUpdate.frameProjection.row(at: 1)?.cells[0].grapheme == "Z")
        #expect(update.surfaceUpdate.frameProjection.row(at: 0) == nil)
    }

    @Test("Resize produces a full invalidation with the new viewport dimensions")
    func resizeProducesFullInvalidation() async throws {
        let runtime = try GhosttyVTRuntime(cols: 20, rows: 4)

        _ = await runtime.write(Data("hello".utf8))
        _ = await runtime.write(Data())

        let resized = await runtime.resize(
            cols: 24,
            rows: 6,
            cellWidthPx: 8,
            cellHeightPx: 16
        )

        #expect(resized.surfaceState.cols == 24)
        #expect(resized.surfaceState.rows == 6)
        #expect(resized.frameProjection.dirtyState.kind == .full)
        #expect(resized.frameProjection.dirtyState.dirtyRows == [0, 1, 2, 3, 4, 5])
        #expect(resized.frameProjection.rowsByIndex.map(\.index) == [0, 1, 2, 3, 4, 5])

        let clean = await runtime.write(Data())
        #expect(clean.surfaceUpdate.frameProjection.dirtyState.kind == .clean)
    }

    @Test("Viewport scroll produces a full redraw of the visible rows")
    func viewportScrollProducesFullInvalidation() async throws {
        let runtime = try GhosttyVTRuntime(cols: 20, rows: 2)

        _ = await runtime.write(Data("one\r\ntwo\r\nthree".utf8))
        _ = await runtime.write(Data())

        let scrolled = await runtime.scrollViewport(by: -1)

        #expect(scrolled.surfaceState.viewportOffset > 0)
        #expect(scrolled.frameProjection.dirtyState.kind == .full)
        #expect(scrolled.frameProjection.dirtyState.dirtyRows == [0, 1])
        #expect(scrolled.frameProjection.rowsByIndex.map(\.index) == [0, 1])

        let clean = await runtime.write(Data())
        #expect(clean.surfaceUpdate.frameProjection.dirtyState.kind == .clean)
    }

    @Test("Projection selection text spans projected rows")
    func selectionProjectionReturnsVisibleText() {
        let projection = GhosttyTerminalFrameProjection(
            cols: 4,
            rows: 2,
            defaultForegroundPacked: 0xFFFFFF,
            defaultBackgroundPacked: 0x000000,
            dirtyState: .clean,
            rowsByIndex: [
                GhosttyTerminalProjectedRow(
                    index: 0,
                    cells: [
                        GhosttyTerminalProjectedCell(column: 0, grapheme: "a", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 1, grapheme: "b", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 2, grapheme: " ", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 3, grapheme: " ", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                    ],
                    isDirty: false
                ),
                GhosttyTerminalProjectedRow(
                    index: 1,
                    cells: [
                        GhosttyTerminalProjectedCell(column: 0, grapheme: "c", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 1, grapheme: "d", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 2, grapheme: " ", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 3, grapheme: " ", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                    ],
                    isDirty: false
                ),
            ],
            overlay: GhosttyTerminalOverlayProjection(
                selectionRange: GhosttyTerminalSelectionRange(
                    start: .init(row: 0, col: 0),
                    end: .init(row: 1, col: 1)
                ),
                cursor: .init(),
                cursorVisible: false,
                cursorStyle: .block,
                viewportOffset: 0
            )
        )

        #expect(
            projection.text(in: projection.overlay.selectionRange) == "ab\ncd"
        )
    }

    @Test("Projection builder merges partial row updates into a cached frame")
    func mergePartialProjectionKeepsCleanRows() {
        let builder = GhosttyTerminalProjectionBuilder()
        let current = GhosttyTerminalFrameProjection(
            cols: 3,
            rows: 2,
            defaultForegroundPacked: 0xFFFFFF,
            defaultBackgroundPacked: 0x000000,
            dirtyState: .clean,
            rowsByIndex: [
                GhosttyTerminalProjectedRow(
                    index: 0,
                    cells: [
                        GhosttyTerminalProjectedCell(column: 0, grapheme: "a", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 1, grapheme: "b", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 2, grapheme: "c", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                    ],
                    isDirty: false
                ),
                GhosttyTerminalProjectedRow(
                    index: 1,
                    cells: [
                        GhosttyTerminalProjectedCell(column: 0, grapheme: "d", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 1, grapheme: "e", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 2, grapheme: "f", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                    ],
                    isDirty: false
                ),
            ],
            overlay: GhosttyTerminalOverlayProjection(
                selectionRange: nil,
                cursor: .init(),
                cursorVisible: false,
                cursorStyle: .block,
                viewportOffset: 0
            )
        )

        let update = GhosttyTerminalFrameProjection(
            cols: 3,
            rows: 2,
            defaultForegroundPacked: 0xFFFFFF,
            defaultBackgroundPacked: 0x000000,
            dirtyState: GhosttyTerminalDirtyState(kind: .partial, dirtyRows: [1]),
            rowsByIndex: [
                GhosttyTerminalProjectedRow(
                    index: 1,
                    cells: [
                        GhosttyTerminalProjectedCell(column: 0, grapheme: "x", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 1, grapheme: "y", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                        GhosttyTerminalProjectedCell(column: 2, grapheme: "z", foregroundPacked: 0xFFFFFF, backgroundPacked: 0x000000),
                    ],
                    isDirty: true
                ),
            ],
            overlay: GhosttyTerminalOverlayProjection(
                selectionRange: nil,
                cursor: .init(),
                cursorVisible: false,
                cursorStyle: .block,
                viewportOffset: 0
            )
        )

        let merged = builder.merge(current: current, update: update)
        #expect(merged.row(at: 0)?.cells.map(\.grapheme).joined() == "abc")
        #expect(merged.row(at: 1)?.cells.map(\.grapheme).joined() == "xyz")
        #expect(merged.dirtyState.dirtyRows == [1])
    }
}
