import Foundation

public struct GhosttyTerminalCursor: Equatable, Sendable {
    public var row: Int
    public var col: Int

    public init(row: Int = 0, col: Int = 0) {
        self.row = row
        self.col = col
    }
}

public enum GhosttyTerminalCursorStyle: Sendable, Equatable {
    case block
    case underline
    case beam
    case hollowBlock
}

public struct GhosttyTerminalSelectionPoint: Equatable, Sendable {
    public var row: Int
    public var col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

public struct GhosttyTerminalSelectionRange: Equatable, Sendable {
    public var start: GhosttyTerminalSelectionPoint
    public var end: GhosttyTerminalSelectionPoint

    public init(
        start: GhosttyTerminalSelectionPoint,
        end: GhosttyTerminalSelectionPoint
    ) {
        self.start = start
        self.end = end
    }
}
