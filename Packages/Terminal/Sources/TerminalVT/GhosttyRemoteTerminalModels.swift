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

public enum GhosttyRemoteTerminalConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case failed(String)
    case closed
}

public enum GhosttyTerminalSpecialKey: Equatable, Sendable {
    case enter
    case escape
    case tab
    case backtab
    case backspace
    case delete
    case up
    case down
    case left
    case right
    case pageUp
    case pageDown
    case home
    case end
    case interrupt
}
