import Foundation
@preconcurrency import CGhosttyVT

private struct GhosttyScreenSize {
    var totalRows: Int
    var cols: Int
}

extension GhosttyVTCore {
    func screenText() -> String {
        guard let terminal else { return "" }
        let size = screenSize(for: terminal)
        guard size.totalRows > 0, size.cols > 0 else { return "" }

        var lines: [String] = []
        lines.reserveCapacity(size.totalRows)
        for row in 0..<size.totalRows {
            lines.append(screenLineText(terminal: terminal, row: row, cols: size.cols))
        }

        return lines.joined(separator: "\n")
    }

    private func screenSize(for terminal: GhosttyTerminal) -> GhosttyScreenSize {
        var totalRows = 0
        var cols: UInt16 = 0
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_TOTAL_ROWS, &totalRows)
        _ = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &cols)
        return GhosttyScreenSize(totalRows: totalRows, cols: Int(cols))
    }

    private func screenLineText(
        terminal: GhosttyTerminal,
        row: Int,
        cols: Int
    ) -> String {
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(cols)

        for col in 0..<cols {
            scalars.append(screenScalar(terminal: terminal, row: row, col: col))
        }

        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    private func screenScalar(
        terminal: GhosttyTerminal,
        row: Int,
        col: Int
    ) -> UnicodeScalar {
        guard var gridRef = gridRef(terminal: terminal, row: row, col: col) else {
            return " "
        }

        var cell: GhosttyCell = 0
        guard ghostty_grid_ref_cell(&gridRef, &cell) == GHOSTTY_SUCCESS else {
            return " "
        }

        var hasText = false
        _ = ghostty_cell_get(cell, GHOSTTY_CELL_DATA_HAS_TEXT, &hasText)
        guard hasText else { return " " }

        return graphemes(for: &gridRef)
            .compactMap(UnicodeScalar.init)
            .first ?? " "
    }

    private func gridRef(
        terminal: GhosttyTerminal,
        row: Int,
        col: Int
    ) -> GhosttyGridRef? {
        var gridRef = GhosttyGridRef(
            size: MemoryLayout<GhosttyGridRef>.size,
            node: nil,
            x: 0,
            y: 0
        )
        let point = GhosttyPoint(
            tag: GHOSTTY_POINT_TAG_SCREEN,
            value: GhosttyPointValue(
                coordinate: GhosttyPointCoordinate(
                    x: UInt16(col),
                    y: UInt32(row)
                )
            )
        )

        guard ghostty_terminal_grid_ref(terminal, point, &gridRef) == GHOSTTY_SUCCESS else {
            return nil
        }

        return gridRef
    }

    private func graphemes(
        for gridRef: inout GhosttyGridRef
    ) -> [UInt32] {
        var graphemeCount = 0
        let probeResult = ghostty_grid_ref_graphemes(&gridRef, nil, 0, &graphemeCount)
        guard probeResult == GHOSTTY_OUT_OF_SPACE, graphemeCount > 0 else {
            return []
        }

        var buffer = Array(repeating: UInt32(0), count: graphemeCount)
        _ = buffer.withUnsafeMutableBufferPointer { pointer in
            var required = graphemeCount
            return ghostty_grid_ref_graphemes(
                &gridRef,
                pointer.baseAddress,
                pointer.count,
                &required
            )
        }
        return buffer
    }
}
