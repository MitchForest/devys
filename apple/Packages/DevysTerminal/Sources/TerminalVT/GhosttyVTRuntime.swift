public import Foundation
public import TerminalCore
@preconcurrency import CGhosttyVT

public actor GhosttyVTRuntime {
    private let core: GhosttyVTCore

    public init(
        cols: Int,
        rows: Int,
        scrollbackMax: Int = 100_000,
        appearance: GhosttyTerminalAppearance = .defaultDark
    ) throws {
        self.core = try GhosttyVTCore(
            cols: cols,
            rows: rows,
            scrollbackMax: scrollbackMax,
            appearance: appearance
        )
    }

    public func write(_ data: Data) -> GhosttyVTWriteResult {
        core.write(data)
    }

    public func resize(
        cols: Int,
        rows: Int,
        cellWidthPx: Int,
        cellHeightPx: Int
    ) -> GhosttyTerminalSurfaceUpdate {
        core.resize(
            cols: cols,
            rows: rows,
            cellWidthPx: cellWidthPx,
            cellHeightPx: cellHeightPx
        )
        return core.surfaceUpdate()
    }

    public func scrollViewport(by delta: Int) -> GhosttyTerminalSurfaceUpdate {
        core.scrollViewport(by: delta)
        return core.surfaceUpdate()
    }

    public func pasteData(for text: String) -> Data {
        core.pasteData(for: text)
    }

    public func mouseWheelData(for event: GhosttyTerminalMouseWheelEvent) -> Data {
        core.mouseWheelData(for: event)
    }

    public func inputData(for event: GhosttyTerminalKeyEvent) -> Data {
        core.keyData(for: event, optionAsAlt: .enabled)
    }

    public func screenText() -> String {
        core.screenText()
    }

    public func screenLines() -> [GhosttyTerminalScreenLine] {
        core.screenLines()
    }

    public func updateAppearance(
        _ appearance: GhosttyTerminalAppearance
    ) -> GhosttyTerminalSurfaceUpdate {
        core.configureAppearance(appearance)
        return core.surfaceUpdate()
    }
}

enum GhosttyTerminalOptionAsAlt: Sendable, Equatable {
    case disabled
    case enabled
    case leftOnly
    case rightOnly
}

public struct GhosttyVTWriteResult: Sendable {
    public var surfaceUpdate: GhosttyTerminalSurfaceUpdate
    public var outboundWrites: [Data]
    public var title: String
    public var workingDirectory: String?
    public var bellCountDelta: Int

    public init(
        surfaceUpdate: GhosttyTerminalSurfaceUpdate,
        outboundWrites: [Data],
        title: String,
        workingDirectory: String?,
        bellCountDelta: Int
    ) {
        self.surfaceUpdate = surfaceUpdate
        self.outboundWrites = outboundWrites
        self.title = title
        self.workingDirectory = workingDirectory
        self.bellCountDelta = bellCountDelta
    }
}

public enum GhosttyTerminalMouseWheelDirection: Sendable, Equatable {
    // swiftlint:disable:next identifier_name
    case up
    case down
}

public struct GhosttyTerminalMouseWheelEvent: Sendable, Equatable {
    public var direction: GhosttyTerminalMouseWheelDirection
    public var positionX: Float
    public var positionY: Float
    public var screenWidthPx: UInt32
    public var screenHeightPx: UInt32
    public var cellWidthPx: UInt32
    public var cellHeightPx: UInt32

    public init(
        direction: GhosttyTerminalMouseWheelDirection,
        positionX: Float,
        positionY: Float,
        screenWidthPx: UInt32,
        screenHeightPx: UInt32,
        cellWidthPx: UInt32,
        cellHeightPx: UInt32
    ) {
        self.direction = direction
        self.positionX = positionX
        self.positionY = positionY
        self.screenWidthPx = screenWidthPx
        self.screenHeightPx = screenHeightPx
        self.cellWidthPx = max(1, cellWidthPx)
        self.cellHeightPx = max(1, cellHeightPx)
    }
}

public enum GhosttyVTRuntimeError: Error {
    case failedToCreateTerminal
    case failedToCreateRenderState
}
