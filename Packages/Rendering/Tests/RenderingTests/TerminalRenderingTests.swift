import Metal
import Testing
import simd
@testable import Rendering

@Suite("Terminal Rendering Tests")
struct TerminalRenderingTests {
    @Test("Terminal cell GPU defaults are stable")
    func terminalCellDefaults() {
        let cell = TerminalCellGPU()

        #expect(cell.position == .zero)
        #expect(cell.size == .zero)
        #expect(cell.uvOrigin == .zero)
        #expect(cell.uvSize == .zero)
        #expect(cell.flags == 0)
        #expect(cell.padding == 0)
    }

    @Test("Terminal glyph atlas preloads ASCII and block glyphs without runtime misses")
    @MainActor
    func glyphAtlasPreloadsCommonTerminalGlyphs() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var mutationCount = 0

        let atlas = TerminalGlyphAtlas(
            device: device,
            fontName: "Menlo",
            fontSize: 13,
            cellWidth: 8,
            cellHeight: 16,
            onAtlasMutation: { mutationCount += 1 }
        )

        let first = atlas.entry(for: "A", cellSpan: 1)
        let second = atlas.entry(for: "A", cellSpan: 1)
        let block = atlas.entry(for: "\u{2588}", cellSpan: 1)

        #expect(first == second)
        #expect(block != .empty)
        #expect(mutationCount == 0)
        #expect(atlas.texture != nil)
        #expect(atlas.fullTextureUploadCount == 1)
        #expect(atlas.partialTextureUploadCount == 0)
    }

    @Test("Terminal glyph atlas batches runtime misses into one partial upload")
    @MainActor
    func glyphAtlasBatchesRuntimeMisses() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        var mutationCount = 0

        let atlas = TerminalGlyphAtlas(
            device: device,
            fontName: "Menlo",
            fontSize: 13,
            cellWidth: 8,
            cellHeight: 16,
            onAtlasMutation: { mutationCount += 1 }
        )

        atlas.prepareGlyphs(
            for: [
                TerminalGlyphRequest(grapheme: "é", cellSpan: 1),
                TerminalGlyphRequest(grapheme: "Ω", cellSpan: 1),
            ]
        )

        let accented = atlas.entry(for: "é", cellSpan: 1)
        let omega = atlas.entry(for: "Ω", cellSpan: 1)

        #expect(accented != .empty)
        #expect(omega != .empty)
        #expect(mutationCount == 1)
        #expect(atlas.fullTextureUploadCount == 1)
        #expect(atlas.partialTextureUploadCount == 1)
    }

    @Test("Terminal special glyph rasterizer fills block elements without seams")
    func specialGlyphRasterizerFillsBlockElements() throws {
        let fullBlock = try #require(
            TerminalSpecialGlyphRasterizer.bitmap(
                for: "\u{2588}",
                cellWidth: 8,
                cellHeight: 8
            )
        )
        let upperHalf = try #require(
            TerminalSpecialGlyphRasterizer.bitmap(
                for: "\u{2580}",
                cellWidth: 8,
                cellHeight: 8
            )
        )
        let leftHalf = try #require(
            TerminalSpecialGlyphRasterizer.bitmap(
                for: "\u{258C}",
                cellWidth: 8,
                cellHeight: 8
            )
        )

        #expect(fullBlock.rgba.filter { $0 == 255 }.count == 8 * 8 * 4)
        #expect(alpha(atX: 1, y: 1, bitmap: upperHalf) == 255)
        #expect(alpha(atX: 1, y: 6, bitmap: upperHalf) == 0)
        #expect(alpha(atX: 1, y: 1, bitmap: leftHalf) == 255)
        #expect(alpha(atX: 6, y: 1, bitmap: leftHalf) == 0)
    }

    @Test("Terminal cell buffer sync packs GPU cells into the backing buffer")
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
            TerminalCellGPU(
                position: SIMD2(30, 40),
                size: SIMD2(8, 16),
                foregroundColor: SIMD4(0, 1, 0, 1),
                backgroundColor: SIMD4(0, 0, 0, 1),
                uvOrigin: SIMD2(0.5, 0.6),
                uvSize: SIMD2(0.2, 0.1),
                flags: 0
            ),
        ]

        buffer.setCells(cells)
        buffer.syncToGPU()

        let stored = buffer.currentBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: cells.count)

        #expect(buffer.cellCount == 2)
        #expect(stored[0].position == cells[0].position)
        #expect(stored[0].flags == cells[0].flags)
        #expect(stored[1].position == cells[1].position)
        #expect(stored[1].uvOrigin == cells[1].uvOrigin)
    }

    @Test("Terminal cell buffer partial sync updates only the active buffer")
    @MainActor
    func cellBufferPartialSyncTouchesOnlyTheActiveBuffer() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let buffer = TerminalCellBuffer(device: device, initialCapacity: 2)
        let initialCells = [
            TerminalCellGPU(position: SIMD2(10, 20)),
            TerminalCellGPU(position: SIMD2(30, 40)),
        ]
        buffer.setCells(initialCells)
        buffer.syncToGPU()

        let firstBuffer = buffer.currentBuffer
        let firstStored = firstBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: initialCells.count)
        #expect(firstStored[1].position == initialCells[1].position)

        buffer.advanceBuffer()
        let updatedCells = [
            initialCells[0],
            TerminalCellGPU(position: SIMD2(90, 100)),
        ]
        buffer.setCells(updatedCells, dirtyRanges: [1..<2])
        buffer.syncToGPU()

        let activeStored = buffer.currentBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: updatedCells.count)
        let inactiveStored = firstBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: initialCells.count)

        #expect(activeStored[1].position == updatedCells[1].position)
        #expect(inactiveStored[1].position == initialCells[1].position)
    }

    @Test("Terminal cell buffer clean redraw seeds a rotated buffer with the cached frame")
    @MainActor
    func cellBufferCleanRedrawSeedsRotatedBuffer() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let buffer = TerminalCellBuffer(device: device, initialCapacity: 2)
        let initialCells = [
            TerminalCellGPU(position: SIMD2(10, 20)),
            TerminalCellGPU(position: SIMD2(30, 40)),
        ]

        buffer.setCells(initialCells)
        buffer.syncToGPU()
        buffer.advanceBuffer()
        buffer.syncToGPU()

        let rotatedStored = buffer.currentBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: initialCells.count)

        #expect(rotatedStored[0].position == initialCells[0].position)
        #expect(rotatedStored[1].position == initialCells[1].position)
    }

    @Test("Terminal cell buffer falls back to a full upload when a rotated buffer is not on the prior revision")
    @MainActor
    func cellBufferPartialSyncRebasesAnUnprimedRotatedBuffer() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let buffer = TerminalCellBuffer(device: device, initialCapacity: 2)
        let initialCells = [
            TerminalCellGPU(position: SIMD2(10, 20)),
            TerminalCellGPU(position: SIMD2(30, 40)),
        ]
        buffer.setCells(initialCells)
        buffer.syncToGPU()

        buffer.advanceBuffer()
        let updatedCells = [
            TerminalCellGPU(position: SIMD2(10, 20)),
            TerminalCellGPU(position: SIMD2(90, 100)),
        ]
        buffer.setCells(updatedCells, dirtyRanges: [1..<2])
        buffer.syncToGPU()

        let rotatedStored = buffer.currentBuffer.contents()
            .bindMemory(to: TerminalCellGPU.self, capacity: updatedCells.count)

        #expect(rotatedStored[0].position == updatedCells[0].position)
        #expect(rotatedStored[1].position == updatedCells[1].position)
    }

    @Test("Terminal overlay buffer emits one quad as six vertices")
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

    @Test("Terminal row cache policy invalidates on grid changes and full dirty frames")
    func rowCachePolicy() {
        let initial = TerminalGridSignature(cols: 120, rows: 40)
        let same = TerminalGridSignature(cols: 120, rows: 40)
        let resized = TerminalGridSignature(cols: 100, rows: 40)

        #expect(
            TerminalRowCachePolicy.requiresFullReset(
                previous: nil,
                current: initial,
                isFullDirty: false
            )
        )
        #expect(
            TerminalRowCachePolicy.requiresFullReset(
                previous: initial,
                current: same,
                isFullDirty: true
            )
        )
        #expect(
            TerminalRowCachePolicy.requiresFullReset(
                previous: initial,
                current: resized,
                isFullDirty: false
            )
        )
        #expect(
            TerminalRowCachePolicy.requiresFullReset(
                previous: initial,
                current: same,
                isFullDirty: false
            ) == false
        )
    }

    @Test("Terminal cell packing builds GPU instances from descriptors")
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
            ),
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
        #expect(cells[1].uvOrigin == SIMD2(0.5, 0.6))
    }

    @Test("Terminal cell packing flattens cached rows in row order")
    func terminalCellPackingFlattensRowsInOrder() {
        let row0 = TerminalCellGPU(position: SIMD2(0, 0))
        let row2 = TerminalCellGPU(position: SIMD2(0, 32))
        let flattened = TerminalCellPacking.flattenRows(
            [
                2: [row2],
                0: [row0],
            ],
            totalRows: 3
        )

        #expect(flattened.count == 2)
        #expect(flattened[0].position == row0.position)
        #expect(flattened[1].position == row2.position)
    }

    @Test("Terminal cell packing records row ranges alongside the flattened cells")
    func terminalCellPackingRecordsRowRanges() {
        let row0 = TerminalCellGPU(position: SIMD2(0, 0))
        let row2A = TerminalCellGPU(position: SIMD2(8, 32))
        let row2B = TerminalCellGPU(position: SIMD2(16, 32))
        let packedRows = TerminalCellPacking.packRows(
            [
                2: [row2A, row2B],
                0: [row0],
            ],
            totalRows: 3
        )

        #expect(packedRows.cells.count == 3)
        #expect(packedRows.rowRanges[0] == 0..<1)
        #expect(packedRows.rowRanges[1] == 1..<1)
        #expect(packedRows.rowRanges[2] == 1..<3)
    }
}

private func alpha(
    atX x: Int,
    y: Int,
    bitmap: TerminalSpecialGlyphBitmap
) -> UInt8 {
    let index = ((y * bitmap.width) + x) * 4 + 3
    return bitmap.rgba[index]
}
