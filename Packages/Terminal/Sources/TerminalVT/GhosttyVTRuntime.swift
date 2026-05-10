import Foundation
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

    public func specialKeyData(
        for key: GhosttyTerminalSpecialKey,
        appCursorMode: Bool
    ) -> Data {
        switch key {
        case .enter:
            Data([0x0D])
        case .escape:
            Data([0x1B])
        case .tab:
            Data([0x09])
        case .backtab:
            Data("\u{1B}[Z".utf8)
        case .backspace:
            Data([0x7F])
        case .delete:
            Data("\u{1B}[3~".utf8)
        case .interrupt:
            Data([0x03])
        case .up:
            Data((appCursorMode ? "\u{1B}OA" : "\u{1B}[A").utf8)
        case .down:
            Data((appCursorMode ? "\u{1B}OB" : "\u{1B}[B").utf8)
        case .right:
            Data((appCursorMode ? "\u{1B}OC" : "\u{1B}[C").utf8)
        case .left:
            Data((appCursorMode ? "\u{1B}OD" : "\u{1B}[D").utf8)
        case .home:
            Data((appCursorMode ? "\u{1B}OH" : "\u{1B}[H").utf8)
        case .end:
            Data((appCursorMode ? "\u{1B}OF" : "\u{1B}[F").utf8)
        case .pageUp:
            Data("\u{1B}[5~".utf8)
        case .pageDown:
            Data("\u{1B}[6~".utf8)
        }
    }

    public func controlCharacter(for character: Character) -> Data? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        let value = scalar.value

        switch value {
        case 64...95:
            return Data([UInt8(value - 64)])
        case 97...122:
            return Data([UInt8(value - 96)])
        case 32:
            return Data([0x00])
        default:
            return nil
        }
    }

    public func screenText() -> String {
        core.screenText()
    }

    public func updateAppearance(
        _ appearance: GhosttyTerminalAppearance
    ) -> GhosttyTerminalSurfaceUpdate {
        core.configureAppearance(appearance)
        return core.surfaceUpdate()
    }
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

public enum GhosttyVTRuntimeError: Error {
    case failedToCreateTerminal
    case failedToCreateRenderState
}
