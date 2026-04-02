import SwiftUI
import TerminalCore
import UI

struct IOSTerminalSurfaceView: View {
    @Environment(\.devysTheme) private var theme

    let renderState: TerminalRenderState
    let selectionMode: Bool
    let onTap: () -> Void
    let onSelectionBegin: (Int, Int) -> Void
    let onSelectionMove: (Int, Int) -> Void
    let onSelectionEnd: () -> Void
    let onSelectWord: (Int, Int) -> Void
    let onScroll: (Int) -> Void
    let onViewportSizeChange: (CGSize) -> Void

    @State private var hasStartedSelectionDrag = false

    var body: some View {
        GeometryReader { proxy in
            let grid = gridMetrics(size: proxy.size)

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<renderState.rows, id: \.self) { row in
                        terminalRowView(row: row)
                            .frame(width: grid.contentWidth, alignment: .leading)
                            .frame(height: grid.cellHeight, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                selectionOverlay(grid: grid)
                cursorOverlay(grid: grid)
            }
            .contentShape(Rectangle())
            .gesture(selectionGesture(grid: grid))
            .simultaneousGesture(scrollGesture(grid: grid))
            .simultaneousGesture(tapGesture())
            .simultaneousGesture(doubleTapGesture(grid: grid))
            .onAppear {
                onViewportSizeChange(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                onViewportSizeChange(newSize)
            }
        }
        .clipped()
    }

    private func terminalRowView(row: Int) -> some View {
        let cells = rowCells(for: row)
        let segments = rowSegments(from: cells)

        return HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(verbatim: segment.text)
                    .font(IOSTerminalLayoutMetrics.swiftUIFont)
                    .foregroundStyle(segment.foreground)
                    .background(segment.background)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func selectionOverlay(grid: TerminalGridMetrics) -> some View {
        let rects = selectionRects(grid: grid)
        if !rects.isEmpty {
            Path { path in
                for rect in rects {
                    path.addRect(rect)
                }
            }
            .fill(color(from: AnsiColors.selectionBackground).opacity(0.42))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cursorOverlay(grid: TerminalGridMetrics) -> some View {
        if let cursorRect = cursorRect(grid: grid) {
            let cursorColor = color(from: AnsiColors.cursorColor)
            switch renderState.cursorStyle {
            case .block:
                Rectangle()
                    .fill(cursorColor.opacity(0.32))
                    .frame(width: cursorRect.width, height: cursorRect.height)
                    .position(x: cursorRect.midX, y: cursorRect.midY)
                    .allowsHitTesting(false)
            case .underline:
                Rectangle()
                    .fill(cursorColor.opacity(0.9))
                    .frame(width: cursorRect.width, height: cursorRect.height)
                    .position(x: cursorRect.midX, y: cursorRect.midY)
                    .allowsHitTesting(false)
            case .beam:
                Rectangle()
                    .fill(cursorColor.opacity(0.9))
                    .frame(width: cursorRect.width, height: cursorRect.height)
                    .position(x: cursorRect.midX, y: cursorRect.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func tapGesture() -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { _ in
                onTap()
                if selectionMode == false {
                    hasStartedSelectionDrag = false
                }
            }
    }

    private func doubleTapGesture(grid: TerminalGridMetrics) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let (row, col) = grid.clampedCell(for: value.location)
                onSelectWord(row, col)
                onTap()
            }
    }

    private func selectionGesture(grid: TerminalGridMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard selectionMode else { return }
                let (row, col) = grid.clampedCell(for: value.location)
                if hasStartedSelectionDrag == false {
                    hasStartedSelectionDrag = true
                    onSelectionBegin(row, col)
                } else {
                    onSelectionMove(row, col)
                }
            }
            .onEnded { _ in
                guard selectionMode else { return }
                hasStartedSelectionDrag = false
                onSelectionEnd()
            }
    }

    private func scrollGesture(grid: TerminalGridMetrics) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                guard selectionMode == false else { return }
                let rawLines = -value.translation.height / max(1, grid.cellHeight)
                let lines = Int(rawLines.rounded())
                guard lines != 0 else { return }
                onScroll(lines)
            }
    }

    private func rowCells(for row: Int) -> [TerminalRenderCell] {
        guard row >= 0, row < renderState.visibleRows.count else {
            return []
        }
        return renderState.visibleRows[row]
    }

    private func rowSegments(from cells: [TerminalRenderCell]) -> [TerminalRowSegment] {
        guard !cells.isEmpty else {
            return [TerminalRowSegment(text: "", foreground: theme.text, background: .clear)]
        }

        var segments: [TerminalRowSegment] = []
        var currentText = ""
        var currentForegroundPacked = cells[0].foregroundPacked
        var currentBackgroundPacked = cells[0].backgroundPacked

        for cell in cells {
            if cell.foregroundPacked != currentForegroundPacked || cell.backgroundPacked != currentBackgroundPacked {
                segments.append(
                    TerminalRowSegment(
                        text: currentText,
                        foreground: color(from: currentForegroundPacked),
                        background: color(from: currentBackgroundPacked)
                    )
                )
                currentText = ""
                currentForegroundPacked = cell.foregroundPacked
                currentBackgroundPacked = cell.backgroundPacked
            }
            currentText.append(cell.character)
        }

        segments.append(
            TerminalRowSegment(
                text: currentText,
                foreground: color(from: currentForegroundPacked),
                background: color(from: currentBackgroundPacked)
            )
        )
        return segments
    }

    private func color(from packed: UInt32) -> Color {
        let red = Double((packed >> 16) & 0xFF) / 255
        let green = Double((packed >> 8) & 0xFF) / 255
        let blue = Double(packed & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    private func gridMetrics(size: CGSize) -> TerminalGridMetrics {
        return TerminalGridMetrics(
            cols: max(1, renderState.cols),
            rows: max(1, renderState.rows),
            size: size,
            preferredCellWidth: IOSTerminalLayoutMetrics.cellWidth,
            preferredCellHeight: IOSTerminalLayoutMetrics.cellHeight
        )
    }

    private func selectionRects(grid: TerminalGridMetrics) -> [CGRect] {
        guard let range = renderState.selectionRange else { return [] }

        let startRow = max(0, min(grid.rows - 1, range.start.row.asIndex()))
        let endRow = max(0, min(grid.rows - 1, range.end.row.asIndex()))
        guard endRow >= startRow else { return [] }

        let startCol = max(0, min(grid.cols - 1, range.start.col.asIndex()))
        let endCol = max(0, min(grid.cols - 1, range.end.col.asIndex()))

        var rects: [CGRect] = []
        for row in startRow...endRow {
            let rowStart = row == startRow ? startCol : 0
            let rowEnd = row == endRow ? endCol : (grid.cols - 1)
            guard rowEnd >= rowStart else { continue }
            rects.append(grid.rect(row: row, colStart: rowStart, colEnd: rowEnd))
        }
        return rects
    }

    private func cursorRect(grid: TerminalGridMetrics) -> CGRect? {
        guard renderState.cursorVisible else { return nil }
        guard renderState.viewportOffset == 0 else { return nil }

        let row = max(0, min(grid.rows - 1, renderState.cursor.row))
        let col = max(0, min(grid.cols - 1, renderState.cursor.col))
        let baseRect = grid.rect(row: row, colStart: col, colEnd: col)

        switch renderState.cursorStyle {
        case .block:
            return baseRect
        case .underline:
            let height = max(2, floor(grid.cellHeight * 0.12))
            return CGRect(
                x: baseRect.minX,
                y: baseRect.maxY - height,
                width: baseRect.width,
                height: height
            )
        case .beam:
            let width = max(1.5, floor(grid.cellWidth * 0.12))
            return CGRect(
                x: baseRect.minX,
                y: baseRect.minY,
                width: width,
                height: baseRect.height
            )
        }
    }
}

private struct TerminalRowSegment {
    let text: String
    let foreground: Color
    let background: Color
}

private struct TerminalGridMetrics {
    let cols: Int
    let rows: Int
    let size: CGSize
    let preferredCellWidth: CGFloat
    let preferredCellHeight: CGFloat

    var cellWidth: CGFloat {
        max(1, preferredCellWidth)
    }

    var cellHeight: CGFloat {
        max(1, preferredCellHeight)
    }

    var contentWidth: CGFloat {
        min(size.width, CGFloat(cols) * cellWidth)
    }

    func clampedCell(for point: CGPoint) -> (row: Int, col: Int) {
        let cappedX = max(0, min(point.x, max(0, contentWidth - 1)))
        let col = max(0, min(cols - 1, Int(floor(cappedX / cellWidth))))
        let row = max(0, min(rows - 1, Int(floor(point.y / cellHeight))))
        return (row, col)
    }

    func rect(row: Int, colStart: Int, colEnd: Int) -> CGRect {
        let clampedRow = max(0, min(rows - 1, row))
        let start = max(0, min(cols - 1, colStart))
        let end = max(start, min(cols - 1, colEnd))
        return CGRect(
            x: CGFloat(start) * cellWidth,
            y: CGFloat(clampedRow) * cellHeight,
            width: CGFloat(end - start + 1) * cellWidth,
            height: cellHeight
        )
    }
}
