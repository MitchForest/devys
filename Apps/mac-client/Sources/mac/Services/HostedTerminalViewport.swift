import Foundation

struct HostedTerminalViewportSize: Codable, Equatable, Sendable {
    let cols: Int
    let rows: Int
}

struct HostedTerminalViewport: Equatable, Sendable {
    let size: HostedTerminalViewportSize
    let cellWidthPx: Int
    let cellHeightPx: Int

    init(
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
