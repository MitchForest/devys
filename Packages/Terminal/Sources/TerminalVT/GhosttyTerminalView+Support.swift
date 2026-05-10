import CoreGraphics

struct GhosttyTerminalViewUpdate {
    let surfaceState: GhosttyTerminalSurfaceState
    let frameProjection: GhosttyTerminalFrameProjection
    let appearance: GhosttyTerminalAppearance
    let fontSize: CGFloat
    let selectionMode: Bool
    let focusRequestID: Int

    var renderInputs: GhosttyTerminalRenderInputs {
        GhosttyTerminalRenderInputs(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            fontSize: fontSize
        )
    }
}

struct GhosttyTerminalRenderInputs: Equatable {
    let surfaceState: GhosttyTerminalSurfaceState
    let frameProjection: GhosttyTerminalFrameProjection
    let appearance: GhosttyTerminalAppearance
    let fontSize: CGFloat

    static func == (
        lhs: GhosttyTerminalRenderInputs,
        rhs: GhosttyTerminalRenderInputs
    ) -> Bool {
        lhs.surfaceState == rhs.surfaceState &&
            lhs.frameProjection == rhs.frameProjection &&
            lhs.appearance == rhs.appearance &&
            lhs.fontSize == rhs.fontSize
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

extension GhosttyTerminalHostView {
    static let terminalContentPadding: CGFloat = 2

    var terminalContentRect: CGRect {
        bounds.insetBy(
            dx: Self.terminalContentPadding,
            dy: Self.terminalContentPadding
        )
    }

    func terminalContentPoint(from point: CGPoint) -> CGPoint {
        let contentRect = terminalContentRect
        return CGPoint(
            x: point.x - contentRect.minX,
            y: point.y - contentRect.minY
        )
    }
}
