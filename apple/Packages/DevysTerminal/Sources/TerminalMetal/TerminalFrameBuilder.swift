// TerminalFrameBuilder.swift
// Devys - Turns a TerminalVT frame projection into GPU cell rows.
// Colors arrive pre-resolved as packed RGB in the projection (the
// appearance model in TerminalVT owns palette mapping), so the
// renderer never imports design-system tokens.

public import TerminalVT

public enum TerminalFrameBuilder {
    @MainActor
    public static func descriptors(
        from projection: TerminalFrameProjection,
        atlas: TerminalGlyphAtlas
    ) -> [Int: [TerminalCellDescriptor]] {
        var rows: [Int: [TerminalCellDescriptor]] = [:]
        for row in projection.rowsByIndex {
            rows[row.index] = row.cells.compactMap { cell in
                guard cell.isRenderable else { return nil }
                return TerminalCellDescriptor(
                    column: cell.column,
                    cellSpan: cell.isWide ? 2 : 1,
                    foregroundColor: colorVector(cell.foregroundPacked),
                    backgroundColor: colorVector(cell.backgroundPacked),
                    glyph: atlas.entry(for: cell.normalizedGrapheme, cellSpan: cell.isWide ? 2 : 1),
                    flags: cell.isBold ? .bold : []
                )
            }
        }
        return rows
    }

    @MainActor
    public static func gpuRows(
        from projection: TerminalFrameProjection,
        atlas: TerminalGlyphAtlas,
        cellWidthPx: Float,
        cellHeightPx: Float
    ) -> [Int: [TerminalCellGPU]] {
        let descriptorsByRow = descriptors(from: projection, atlas: atlas)
        var rows: [Int: [TerminalCellGPU]] = [:]
        for (row, descriptors) in descriptorsByRow {
            rows[row] = TerminalCellPacking.gpuCells(
                forRow: row,
                cells: descriptors,
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
        }
        return rows
    }

    public static func colorVector(_ packed: UInt32) -> SIMD4<Float> {
        let red = Float((packed >> 16) & 0xFF) / 255
        let green = Float((packed >> 8) & 0xFF) / 255
        let blue = Float(packed & 0xFF) / 255
        return SIMD4(red, green, blue, 1)
    }
}
