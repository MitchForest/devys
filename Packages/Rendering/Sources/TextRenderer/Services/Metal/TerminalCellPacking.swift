import Foundation
import simd

public struct TerminalPackedRows {
    public let cells: [TerminalCellGPU]
    public let rowRanges: [Int: Range<Int>]

    public init(
        cells: [TerminalCellGPU],
        rowRanges: [Int: Range<Int>]
    ) {
        self.cells = cells
        self.rowRanges = rowRanges
    }
}

public struct TerminalCellDescriptor: Sendable, Equatable {
    public let column: Int
    public let cellSpan: Int
    public let foregroundColor: SIMD4<Float>
    public let backgroundColor: SIMD4<Float>
    public let glyph: TerminalGlyphAtlasEntry
    public let flags: TerminalCellFlags

    public init(
        column: Int,
        cellSpan: Int,
        foregroundColor: SIMD4<Float>,
        backgroundColor: SIMD4<Float>,
        glyph: TerminalGlyphAtlasEntry,
        flags: TerminalCellFlags = []
    ) {
        self.column = column
        self.cellSpan = max(cellSpan, 1)
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.glyph = glyph
        self.flags = flags
    }
}

public enum TerminalCellPacking {
    public static func gpuCells(
        forRow rowIndex: Int,
        cells: [TerminalCellDescriptor],
        cellWidthPx: Float,
        cellHeightPx: Float
    ) -> [TerminalCellGPU] {
        cells.map { cell in
            TerminalCellGPU(
                position: SIMD2(
                    Float(cell.column) * cellWidthPx,
                    Float(rowIndex) * cellHeightPx
                ),
                size: SIMD2(
                    cellWidthPx * Float(cell.cellSpan),
                    cellHeightPx
                ),
                foregroundColor: cell.foregroundColor,
                backgroundColor: cell.backgroundColor,
                uvOrigin: cell.glyph.uvOrigin,
                uvSize: cell.glyph.uvSize,
                flags: cell.flags.rawValue
            )
        }
    }

    public static func flattenRows(
        _ rowsByIndex: [Int: [TerminalCellGPU]],
        totalRows: Int
    ) -> [TerminalCellGPU] {
        packRows(rowsByIndex, totalRows: totalRows).cells
    }

    public static func packRows(
        _ rowsByIndex: [Int: [TerminalCellGPU]],
        totalRows: Int
    ) -> TerminalPackedRows {
        var cells: [TerminalCellGPU] = []
        var rowRanges: [Int: Range<Int>] = [:]

        for rowIndex in 0..<max(totalRows, 0) {
            let startIndex = cells.count
            let rowCells = rowsByIndex[rowIndex] ?? []
            cells.append(contentsOf: rowCells)
            rowRanges[rowIndex] = startIndex..<cells.count
        }

        return TerminalPackedRows(cells: cells, rowRanges: rowRanges)
    }
}
