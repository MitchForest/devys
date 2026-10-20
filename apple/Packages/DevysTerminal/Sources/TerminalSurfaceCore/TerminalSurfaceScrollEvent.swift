public import TerminalVT

public struct TerminalSurfaceScrollEvent: Sendable, Equatable {
    public var lines: Int
    public var positionX: Float
    public var positionY: Float
    public var screenWidthPx: UInt32
    public var screenHeightPx: UInt32
    public var cellWidthPx: UInt32
    public var cellHeightPx: UInt32

    public init(
        lines: Int,
        positionX: Float = 0,
        positionY: Float = 0,
        screenWidthPx: UInt32 = 1,
        screenHeightPx: UInt32 = 1,
        cellWidthPx: UInt32 = 1,
        cellHeightPx: UInt32 = 1
    ) {
        self.lines = lines
        self.positionX = positionX
        self.positionY = positionY
        self.screenWidthPx = max(1, screenWidthPx)
        self.screenHeightPx = max(1, screenHeightPx)
        self.cellWidthPx = max(1, cellWidthPx)
        self.cellHeightPx = max(1, cellHeightPx)
    }

    public func mouseWheelEvent(
        direction: GhosttyTerminalMouseWheelDirection
    ) -> GhosttyTerminalMouseWheelEvent {
        GhosttyTerminalMouseWheelEvent(
            direction: direction,
            positionX: positionX,
            positionY: positionY,
            screenWidthPx: screenWidthPx,
            screenHeightPx: screenHeightPx,
            cellWidthPx: cellWidthPx,
            cellHeightPx: cellHeightPx
        )
    }
}
