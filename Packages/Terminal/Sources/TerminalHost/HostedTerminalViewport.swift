import Foundation

public struct HostedTerminalViewportSize: Codable, Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

public struct HostedTerminalViewport: Equatable, Sendable {
    public let size: HostedTerminalViewportSize
    public let cellWidthPx: Int
    public let cellHeightPx: Int

    public init(
        cols: Int,
        rows: Int,
        cellWidthPx: Int,
        cellHeightPx: Int
    ) {
        self.size = HostedTerminalViewportSize(cols: cols, rows: rows)
        self.cellWidthPx = cellWidthPx
        self.cellHeightPx = cellHeightPx
    }
}
