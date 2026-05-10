// TerminalVTFacade.swift
// Devys - Canonical TerminalVT public surface names.

public typealias TerminalColorScheme = GhosttyTerminalColorScheme
public typealias TerminalColor = GhosttyTerminalColor
public typealias TerminalAppearance = GhosttyTerminalAppearance

public typealias TerminalCursor = GhosttyTerminalCursor
public typealias TerminalCursorStyle = GhosttyTerminalCursorStyle
public typealias TerminalSelectionPoint = GhosttyTerminalSelectionPoint
public typealias TerminalSelectionRange = GhosttyTerminalSelectionRange
public typealias TerminalSpecialKey = GhosttyTerminalSpecialKey

public typealias TerminalDirtyKind = GhosttyTerminalDirtyKind
public typealias TerminalDirtyState = GhosttyTerminalDirtyState
public typealias TerminalProjectedCell = GhosttyTerminalProjectedCell
public typealias TerminalProjectedRow = GhosttyTerminalProjectedRow
public typealias TerminalOverlayProjection = GhosttyTerminalOverlayProjection
public typealias TerminalSurfaceState = GhosttyTerminalSurfaceState
public typealias TerminalFrameProjection = GhosttyTerminalFrameProjection
public typealias TerminalSurfaceUpdate = GhosttyTerminalSurfaceUpdate
public typealias TerminalProjectionBuilder = GhosttyTerminalProjectionBuilder

public typealias TerminalStartupPhase = GhosttyTerminalStartupPhase
public typealias TerminalSession = GhosttyTerminalSession
public typealias TerminalView = GhosttyTerminalView
public typealias TerminalRemoteController = GhosttyRemoteTerminalController
public typealias TerminalVTRuntime = GhosttyVTRuntime
public typealias TerminalVTRuntimeError = GhosttyVTRuntimeError
public typealias TerminalRendererWarmup = GhosttyTerminalRendererWarmup

public extension TerminalAppearance {
    static var terminalDarkPalette: [TerminalColor] {
        ghosttyDarkPalette
    }

    static var terminalLightPalette: [TerminalColor] {
        ghosttyLightPalette
    }
}
