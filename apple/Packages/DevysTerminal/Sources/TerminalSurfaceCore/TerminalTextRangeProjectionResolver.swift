import CoreGraphics
import TerminalCore
import TerminalVT

enum TerminalTextRangeProjectionResolver {
    static func snapshot(
        for ranges: [TerminalTextRange],
        surfaceState: TerminalSurfaceState,
        snapshotRevision: UInt64,
        pixelSize: TerminalSurfacePixelSize?,
        contentPadding: CGFloat
    ) -> TerminalTextRangeProjectionSnapshot {
        guard surfaceState.altScreenMode == false else {
            return .unavailable(.alternateScreen)
        }
        guard let pixelSize else {
            return .unavailable(.runtimeNotReady)
        }

        let totalRows = max(surfaceState.rows, surfaceState.scrollbackRows + surfaceState.rows)
        let visibleTopRow = max(0, totalRows - surfaceState.rows - surfaceState.viewportOffset)
        let visibleBottomRow = visibleTopRow + max(0, surfaceState.rows - 1)
        let cellHeight = Double(pixelSize.cellHeightPoints)
        let padding = Double(contentPadding)

        let projections = ranges.compactMap { range -> TerminalTextRangeProjection? in
            let rangeStartRow = min(range.start.row, range.end.row)
            let rangeEndRow = max(range.start.row, range.end.row)
            let visibleStart = max(rangeStartRow, visibleTopRow)
            let visibleEnd = min(rangeEndRow, visibleBottomRow)
            guard visibleStart <= visibleEnd else {
                return nil
            }

            let visibleStartRow = visibleStart - visibleTopRow
            let visibleEndRow = visibleEnd - visibleTopRow
            let rowCount = visibleEndRow - visibleStartRow + 1
            return TerminalTextRangeProjection(
                range: range,
                visibleStartRow: visibleStartRow,
                visibleEndRow: visibleEndRow,
                topY: padding + Double(visibleStartRow) * cellHeight,
                height: Double(rowCount) * cellHeight
            )
        }

        return TerminalTextRangeProjectionSnapshot(
            snapshotRevision: snapshotRevision,
            projections: projections
        )
    }
}
