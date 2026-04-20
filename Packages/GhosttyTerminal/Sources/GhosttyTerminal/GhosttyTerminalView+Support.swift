import GhosttyTerminalCore

struct GhosttyTerminalRenderInputs: Equatable {
    let surfaceState: GhosttyTerminalSurfaceState
    let frameProjection: GhosttyTerminalFrameProjection
    let appearance: GhosttyTerminalAppearance

    static func == (
        lhs: GhosttyTerminalRenderInputs,
        rhs: GhosttyTerminalRenderInputs
    ) -> Bool {
        lhs.surfaceState == rhs.surfaceState &&
            lhs.frameProjection == rhs.frameProjection &&
            lhs.appearance == rhs.appearance
    }
}

struct GhosttyTerminalMetalViewConfiguration: Equatable {
    let isPaused: Bool
    let enableSetNeedsDisplay: Bool
    let preferredFramesPerSecond: Int
    let framebufferOnly: Bool

    static let onDemand = GhosttyTerminalMetalViewConfiguration(
        isPaused: true,
        enableSetNeedsDisplay: true,
        preferredFramesPerSecond: 60,
        framebufferOnly: true
    )
}
