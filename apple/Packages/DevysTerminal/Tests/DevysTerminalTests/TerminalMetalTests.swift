import Metal
@testable import TerminalMetal
import TerminalVT
import Testing

/// Metal renderer facts: font-stack fallback resolution, glyph atlas
/// packing, frame building, the row cache, and Bundle.module shader
/// compilation - all device-backed where a GPU exists.
@Suite
struct TerminalMetalTests {
    @Test
    func nerdFontSymbolsResolveThroughBundledFallback() {
        let fontStack = TerminalFontStack(primaryFontName: "Menlo-Regular", fontSize: 13)

        let folder = fontStack.resolve(grapheme: "\u{f07b}")
        let javascript = fontStack.resolve(grapheme: "\u{e781}")

        #expect(folder.isMissing == false)
        #expect(javascript.isMissing == false)
        #expect(isNerdFontSymbolIdentifier(folder.fontIdentifier))
        #expect(isNerdFontSymbolIdentifier(javascript.fontIdentifier))
        #expect(folder.fontIdentifier != TerminalFontStack.specialRasterizerFontIdentifier)
        #expect(javascript.fontIdentifier != TerminalFontStack.specialRasterizerFontIdentifier)
    }

    @Test
    func privateUseSymbolsAreNotSpecialRasterized() {
        #expect(TerminalSpecialGlyphRasterizer.canRasterize("\u{f07b}") == false)
        #expect(
            TerminalSpecialGlyphRasterizer.bitmap(
                for: "\u{f07b}",
                cellWidth: 12,
                cellHeight: 24
            ) == nil
        )
    }

    @Test
    func blockElementsStillUseSpecialRasterizer() throws {
        #expect(TerminalSpecialGlyphRasterizer.canRasterize("\u{2588}"))

        let bitmap = try #require(
            TerminalSpecialGlyphRasterizer.bitmap(
                for: "\u{2588}",
                cellWidth: 12,
                cellHeight: 24
            )
        )
        #expect(alphaSum(bitmap.rgba) > 0)
    }

    @Test
    @MainActor
    func nerdFontIconBitmapsRenderDistinctShapes() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let atlas = TerminalGlyphAtlas(
            device: device,
            fontName: "Menlo-Regular",
            fontSize: 13,
            cellWidth: 8,
            cellHeight: 17,
            scaleFactor: 2,
            atlasSize: 512
        )

        let folder = try #require(atlas.renderedBitmapForTesting(grapheme: "\u{f07b}", cellSpan: 1))
        let javascript = try #require(atlas.renderedBitmapForTesting(grapheme: "\u{e781}", cellSpan: 1))

        #expect(alphaSum(folder) > 0)
        #expect(alphaSum(javascript) > 0)
        #expect(folder != javascript)
    }

    @Test
    func gridSignatureClampsDimensions() {
        let grid = TerminalGridSignature(cols: 0, rows: 0)

        #expect(grid.cols == 1)
        #expect(grid.rows == 1)
    }

    @Test
    func terminalCellPackingBuildsGPUCells() {
        let descriptors = [
            TerminalCellDescriptor(
                column: 2,
                cellSpan: 1,
                foregroundColor: SIMD4(1, 0, 0, 1),
                backgroundColor: SIMD4(0, 0, 0, 1),
                glyph: TerminalGlyphAtlasEntry(
                    uvOrigin: SIMD2(0.1, 0.2),
                    uvSize: SIMD2(0.3, 0.4)
                ),
                flags: .bold
            ),
            TerminalCellDescriptor(
                column: 4,
                cellSpan: 2,
                foregroundColor: SIMD4(0, 1, 0, 1),
                backgroundColor: SIMD4(0, 0, 1, 1),
                glyph: TerminalGlyphAtlasEntry(
                    uvOrigin: SIMD2(0.5, 0.6),
                    uvSize: SIMD2(0.2, 0.1)
                )
            )
        ]

        let cells = TerminalCellPacking.gpuCells(
            forRow: 3,
            cells: descriptors,
            cellWidthPx: 8,
            cellHeightPx: 16
        )

        #expect(cells.count == 2)
        #expect(cells[0].position == SIMD2(16, 48))
        #expect(cells[0].size == SIMD2(8, 16))
        #expect(cells[0].flags == TerminalCellFlags.bold.rawValue)
        #expect(cells[1].position == SIMD2(32, 48))
        #expect(cells[1].size == SIMD2(16, 16))
    }

    @Test
    func terminalCellPackingRecordsRowRanges() {
        let row0 = TerminalCellGPU(position: SIMD2(0, 0))
        let row2A = TerminalCellGPU(position: SIMD2(8, 32))
        let row2B = TerminalCellGPU(position: SIMD2(16, 32))
        let packedRows = TerminalCellPacking.packRows(
            [
                2: [row2A, row2B],
                0: [row0]
            ],
            totalRows: 3
        )

        #expect(packedRows.cells.count == 3)
        #expect(packedRows.rowRanges[0] == 0..<1)
        #expect(packedRows.rowRanges[1] == 1..<1)
        #expect(packedRows.rowRanges[2] == 1..<3)
    }

    @Test
    @MainActor
    func cellBufferSyncPacksCells() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let buffer = TerminalCellBuffer(device: device, initialCapacity: 2)
        let cells = [
            TerminalCellGPU(
                position: SIMD2(10, 20),
                size: SIMD2(8, 16),
                foregroundColor: SIMD4(1, 0, 0, 1),
                backgroundColor: SIMD4(0, 0, 0, 1),
                uvOrigin: SIMD2(0.1, 0.2),
                uvSize: SIMD2(0.3, 0.4),
                flags: TerminalCellFlags.bold.rawValue
            ),
            TerminalCellGPU(position: SIMD2(30, 40))
        ]

        buffer.setCells(cells)
        buffer.syncToGPU()

        let stored = buffer.currentBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: cells.count)

        #expect(buffer.cellCount == 2)
        #expect(stored[0].position == cells[0].position)
        #expect(stored[0].flags == cells[0].flags)
        #expect(stored[1].position == cells[1].position)
    }

    @Test
    @MainActor
    func overlayBufferPacksQuadVertices() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let buffer = TerminalOverlayBuffer(device: device, initialCapacity: 6)
        let color = SIMD4<Float>(0.2, 0.4, 0.6, 0.8)

        buffer.addQuad(x: 4, y: 8, width: 10, height: 12, color: color)
        buffer.syncToGPU()

        let stored = try #require(buffer.currentBuffer?.contents())
            .bindMemory(to: TerminalOverlayVertex.self, capacity: 6)

        #expect(buffer.vertexCount == 6)
        #expect(stored[0].position == SIMD2(4, 8))
        #expect(stored[1].position == SIMD2(14, 8))
        #expect(stored[5].position == SIMD2(4, 20))
        #expect(stored[0].color == color)
    }

    @Test
    @MainActor
    func frameBuilderProjectsRenderableCellsIntoGPURows() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let atlas = TerminalGlyphAtlas(
            device: device,
            fontName: "Menlo-Regular",
            fontSize: 13,
            cellWidth: 8,
            cellHeight: 17,
            scaleFactor: 2,
            atlasSize: 512
        )
        var projection = TerminalFrameProjection.empty(cols: 4, rows: 2)
        projection.rowsByIndex = [
            TerminalProjectedRow(
                index: 0,
                cells: [
                    TerminalProjectedCell(
                        column: 0,
                        grapheme: "a",
                        foregroundPacked: 0xFF0000,
                        backgroundPacked: 0x000000
                    ),
                    TerminalProjectedCell(
                        column: 1,
                        grapheme: "W",
                        foregroundPacked: 0x00FF00,
                        backgroundPacked: 0x0000FF,
                        isWide: true
                    ),
                    TerminalProjectedCell(
                        column: 2,
                        grapheme: "",
                        foregroundPacked: 0x00FF00,
                        backgroundPacked: 0x0000FF,
                        isWideContinuation: true
                    )
                ],
                isDirty: false
            )
        ]

        let rows = TerminalFrameBuilder.gpuRows(
            from: projection,
            atlas: atlas,
            cellWidthPx: 8,
            cellHeightPx: 16
        )

        let row = try #require(rows[0])
        #expect(row.count == 2)
        #expect(row[0].position == SIMD2(0, 0))
        #expect(row[0].foregroundColor == SIMD4(1, 0, 0, 1))
        #expect(row[1].size == SIMD2(16, 16))
    }

    @Test
    func rowCachePolicyResetsOnGridChangeOrFullDirty() {
        let grid = TerminalGridSignature(cols: 80, rows: 24)

        #expect(TerminalRowCachePolicy.requiresFullReset(previous: nil, current: grid, isFullDirty: false))
        #expect(TerminalRowCachePolicy.requiresFullReset(
            previous: TerminalGridSignature(cols: 80, rows: 25),
            current: grid,
            isFullDirty: false
        ))
        #expect(TerminalRowCachePolicy.requiresFullReset(previous: grid, current: grid, isFullDirty: true))
        #expect(TerminalRowCachePolicy.requiresFullReset(previous: grid, current: grid, isFullDirty: false) == false)
    }

    @Test
    @MainActor
    func renderPipelineCompilesShadersFromModuleBundle() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let pipeline = try TerminalRenderPipeline(device: device)

        #expect(pipeline.cellPipeline.label == "Terminal Cell Pipeline")
        #expect(pipeline.overlayPipeline.label == "Terminal Overlay Pipeline")
    }
}

private func alphaSum(_ rgba: [UInt8]) -> Int {
    stride(from: 3, to: rgba.count, by: 4).reduce(0) { sum, index in
        sum + Int(rgba[index])
    }
}

private func isNerdFontSymbolIdentifier(_ identifier: String) -> Bool {
    identifier == "SymbolsNF" || identifier.contains("SymbolsNerdFont")
}
