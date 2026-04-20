import Foundation

public func normalizedSelectionRange(
    _ selection: GhosttyTerminalSelectionRange
) -> GhosttyTerminalSelectionRange {
    if selection.start.row < selection.end.row {
        return selection
    }
    if selection.start.row > selection.end.row {
        return GhosttyTerminalSelectionRange(start: selection.end, end: selection.start)
    }
    if selection.start.col <= selection.end.col {
        return selection
    }
    return GhosttyTerminalSelectionRange(start: selection.end, end: selection.start)
}

public enum GhosttyTerminalDirtyKind: Int, Sendable, Equatable {
    case clean
    case partial
    case full
}

public struct GhosttyTerminalDirtyState: Sendable, Equatable {
    public var kind: GhosttyTerminalDirtyKind
    public var dirtyRows: [Int]

    public init(kind: GhosttyTerminalDirtyKind, dirtyRows: [Int] = []) {
        self.kind = kind
        self.dirtyRows = dirtyRows
    }

    public static let clean = GhosttyTerminalDirtyState(kind: .clean)
}

public struct GhosttyTerminalProjectedCell: Sendable, Equatable {
    public var column: Int
    public var grapheme: String
    public var foregroundPacked: UInt32
    public var backgroundPacked: UInt32
    public var isBold: Bool
    public var isWide: Bool
    public var isWideContinuation: Bool

    public init(
        column: Int,
        grapheme: String,
        foregroundPacked: UInt32,
        backgroundPacked: UInt32,
        isBold: Bool = false,
        isWide: Bool = false,
        isWideContinuation: Bool = false
    ) {
        self.column = column
        self.grapheme = grapheme
        self.foregroundPacked = foregroundPacked
        self.backgroundPacked = backgroundPacked
        self.isBold = isBold
        self.isWide = isWide
        self.isWideContinuation = isWideContinuation
    }

    public var isRenderable: Bool {
        isWideContinuation == false
    }

    public var normalizedGrapheme: String {
        grapheme.isEmpty ? " " : grapheme
    }
}

public struct GhosttyTerminalProjectedRow: Sendable, Equatable {
    public var index: Int
    public var cells: [GhosttyTerminalProjectedCell]
    public var isDirty: Bool

    public init(
        index: Int,
        cells: [GhosttyTerminalProjectedCell],
        isDirty: Bool
    ) {
        self.index = index
        self.cells = cells
        self.isDirty = isDirty
    }
}

public struct GhosttyTerminalOverlayProjection: Sendable, Equatable {
    public var selectionRange: GhosttyTerminalSelectionRange?
    public var cursor: GhosttyTerminalCursor
    public var cursorVisible: Bool
    public var cursorStyle: GhosttyTerminalCursorStyle
    public var viewportOffset: Int
    public var cursorColorPacked: UInt32?
    public var cursorWideTail: Bool
    public var cursorPendingWrap: Bool

    public init(
        selectionRange: GhosttyTerminalSelectionRange?,
        cursor: GhosttyTerminalCursor,
        cursorVisible: Bool,
        cursorStyle: GhosttyTerminalCursorStyle,
        viewportOffset: Int,
        cursorColorPacked: UInt32? = nil,
        cursorWideTail: Bool = false,
        cursorPendingWrap: Bool = false
    ) {
        self.selectionRange = selectionRange
        self.cursor = cursor
        self.cursorVisible = cursorVisible
        self.cursorStyle = cursorStyle
        self.viewportOffset = viewportOffset
        self.cursorColorPacked = cursorColorPacked
        self.cursorWideTail = cursorWideTail
        self.cursorPendingWrap = cursorPendingWrap
    }
}

public struct GhosttyTerminalSurfaceState: Sendable, Equatable {
    public var cols: Int
    public var rows: Int
    public var cursor: GhosttyTerminalCursor
    public var cursorVisible: Bool
    public var cursorStyle: GhosttyTerminalCursorStyle
    public var viewportOffset: Int
    public var scrollbackRows: Int
    public var selectionRange: GhosttyTerminalSelectionRange?
    public var appCursorMode: Bool
    public var bracketedPasteMode: Bool
    public var cursorColorPacked: UInt32?
    public var cursorWideTail: Bool
    public var cursorPendingWrap: Bool

    public init(
        cols: Int,
        rows: Int,
        cursor: GhosttyTerminalCursor = GhosttyTerminalCursor(),
        cursorVisible: Bool = true,
        cursorStyle: GhosttyTerminalCursorStyle = .block,
        viewportOffset: Int = 0,
        scrollbackRows: Int = 0,
        selectionRange: GhosttyTerminalSelectionRange? = nil,
        appCursorMode: Bool = false,
        bracketedPasteMode: Bool = false,
        cursorColorPacked: UInt32? = nil,
        cursorWideTail: Bool = false,
        cursorPendingWrap: Bool = false
    ) {
        self.cols = cols
        self.rows = rows
        self.cursor = cursor
        self.cursorVisible = cursorVisible
        self.cursorStyle = cursorStyle
        self.viewportOffset = viewportOffset
        self.scrollbackRows = scrollbackRows
        self.selectionRange = selectionRange
        self.appCursorMode = appCursorMode
        self.bracketedPasteMode = bracketedPasteMode
        self.cursorColorPacked = cursorColorPacked
        self.cursorWideTail = cursorWideTail
        self.cursorPendingWrap = cursorPendingWrap
    }

    public func withSelection(_ selectionRange: GhosttyTerminalSelectionRange?) -> Self {
        var copy = self
        copy.selectionRange = selectionRange
        return copy
    }
}

public struct GhosttyTerminalFrameProjection: Sendable, Equatable {
    public var cols: Int
    public var rows: Int
    public var defaultForegroundPacked: UInt32
    public var defaultBackgroundPacked: UInt32
    public var dirtyState: GhosttyTerminalDirtyState
    public var rowsByIndex: [GhosttyTerminalProjectedRow]
    public var overlay: GhosttyTerminalOverlayProjection

    public init(
        cols: Int,
        rows: Int,
        defaultForegroundPacked: UInt32,
        defaultBackgroundPacked: UInt32,
        dirtyState: GhosttyTerminalDirtyState,
        rowsByIndex: [GhosttyTerminalProjectedRow],
        overlay: GhosttyTerminalOverlayProjection
    ) {
        self.cols = cols
        self.rows = rows
        self.defaultForegroundPacked = defaultForegroundPacked
        self.defaultBackgroundPacked = defaultBackgroundPacked
        self.dirtyState = dirtyState
        self.rowsByIndex = rowsByIndex.sorted { $0.index < $1.index }
        self.overlay = overlay
    }

    public static func empty(
        cols: Int = 1,
        rows: Int = 1,
        defaultForegroundPacked: UInt32 = 0xEDE8E0,
        defaultBackgroundPacked: UInt32 = 0x0C0B0A
    ) -> GhosttyTerminalFrameProjection {
        GhosttyTerminalFrameProjection(
            cols: cols,
            rows: rows,
            defaultForegroundPacked: defaultForegroundPacked,
            defaultBackgroundPacked: defaultBackgroundPacked,
            dirtyState: .clean,
            rowsByIndex: [],
            overlay: GhosttyTerminalOverlayProjection(
                selectionRange: nil,
                cursor: .init(),
                cursorVisible: false,
                cursorStyle: .block,
                viewportOffset: 0,
                cursorColorPacked: nil,
                cursorWideTail: false,
                cursorPendingWrap: false
            )
        )
    }

    public func row(at index: Int) -> GhosttyTerminalProjectedRow? {
        rowsByIndex.first { $0.index == index }
    }

    public func withSelection(_ selectionRange: GhosttyTerminalSelectionRange?) -> Self {
        var copy = self
        copy.overlay.selectionRange = selectionRange
        return copy
    }

    public func text(in selectionRange: GhosttyTerminalSelectionRange?) -> String? {
        guard let selectionRange else { return nil }
        let normalized = normalizedSelectionRange(selectionRange)

        var lines: [String] = []
        for rowIndex in normalized.start.row...normalized.end.row {
            guard let row = row(at: rowIndex) else { continue }
            let startCol = rowIndex == normalized.start.row ? normalized.start.col : 0
            let endCol = rowIndex == normalized.end.row ? normalized.end.col : max(0, row.cells.count - 1)
            guard startCol <= endCol else { continue }

            let selected = row.cells[startCol...min(endCol, max(0, row.cells.count - 1))]
                .filter(\.isRenderable)
                .map(\.grapheme)
                .joined()
                .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            lines.append(selected)
        }

        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public func wordSelection(atRow rowIndex: Int, col: Int) -> GhosttyTerminalSelectionRange? {
        guard let projectedRow = row(at: rowIndex), !projectedRow.cells.isEmpty else { return nil }
        let normalizedColumn = normalizedRenderableColumn(in: projectedRow, col: col)
        guard normalizedColumn >= 0, normalizedColumn < projectedRow.cells.count else { return nil }

        var start = normalizedColumn
        var end = normalizedColumn

        while start > 0, projectedRow.cells[start - 1].isWordBoundary == false {
            start -= 1
        }
        while end < projectedRow.cells.count - 1, projectedRow.cells[end + 1].isWordBoundary == false {
            end += 1
        }

        start = normalizedRenderableColumn(in: projectedRow, col: start)
        end = normalizedRenderableColumn(in: projectedRow, col: end)
        return GhosttyTerminalSelectionRange(
            start: GhosttyTerminalSelectionPoint(row: rowIndex, col: start),
            end: GhosttyTerminalSelectionPoint(row: rowIndex, col: end)
        )
    }

    private func normalizedRenderableColumn(
        in row: GhosttyTerminalProjectedRow,
        col: Int
    ) -> Int {
        let clamped = max(0, min(col, row.cells.count - 1))
        if row.cells[clamped].isRenderable {
            return clamped
        }
        return stride(from: clamped, through: 0, by: -1)
            .first { row.cells[$0].isRenderable } ?? clamped
    }
}

public struct GhosttyTerminalSurfaceUpdate: Sendable, Equatable {
    public var surfaceState: GhosttyTerminalSurfaceState
    public var frameProjection: GhosttyTerminalFrameProjection

    public init(
        surfaceState: GhosttyTerminalSurfaceState,
        frameProjection: GhosttyTerminalFrameProjection
    ) {
        self.surfaceState = surfaceState
        self.frameProjection = frameProjection
    }
}

public struct GhosttyTerminalProjectionBuilder: Sendable {
    public init() {}

    public func merge(
        current: GhosttyTerminalFrameProjection,
        update: GhosttyTerminalFrameProjection
    ) -> GhosttyTerminalFrameProjection {
        if update.dirtyState.kind == .full ||
            current.cols != update.cols ||
            current.rows != update.rows {
            return update
        }

        var mergedRows = Dictionary(uniqueKeysWithValues: current.rowsByIndex.map { ($0.index, $0) })
        for row in update.rowsByIndex {
            mergedRows[row.index] = row
        }

        return GhosttyTerminalFrameProjection(
            cols: update.cols,
            rows: update.rows,
            defaultForegroundPacked: update.defaultForegroundPacked,
            defaultBackgroundPacked: update.defaultBackgroundPacked,
            dirtyState: update.dirtyState,
            rowsByIndex: mergedRows.values.sorted { $0.index < $1.index },
            overlay: update.overlay
        )
    }

    public func applySelection(
        _ selectionRange: GhosttyTerminalSelectionRange?,
        to frameProjection: GhosttyTerminalFrameProjection
    ) -> GhosttyTerminalFrameProjection {
        frameProjection.withSelection(selectionRange)
    }
}

private extension GhosttyTerminalProjectedCell {
    var isWordBoundary: Bool {
        if isRenderable == false {
            return true
        }
        return normalizedGrapheme.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
