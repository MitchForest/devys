// Ported from the reference repo's TerminalSurface host layer (P0-014).
// Shared host plumbing: the per-frame view update value, the MTKView
// drive-mode configurations, and the render-session binding both the
// macOS NSView host and the iOS UIView host conform to.

import CoreGraphics
import TerminalSurfaceCore
import TerminalVT

#if os(macOS)
    import AppKit
#endif

struct GhosttyTerminalViewUpdate {
    let renderSession: TerminalSurfaceRenderSession
    let appearance: TerminalAppearance
    let fontSize: CGFloat
    let selectionMode: Bool
    let focusRequestID: Int
    let isSurfaceVisible: Bool
    let targetPointSize: CGSize
}

struct GhosttyTerminalMetalViewConfiguration: Equatable {
    let isPaused: Bool
    let enableSetNeedsDisplay: Bool
    let preferredFramesPerSecond: Int
    let framebufferOnly: Bool

    /// The macOS drive mode (and the iOS Reduced Motion mode): the host
    /// draws only when the render session invalidates.
    static let onDemand = GhosttyTerminalMetalViewConfiguration(
        isPaused: true,
        enableSetNeedsDisplay: true,
        preferredFramesPerSecond: 60,
        framebufferOnly: true
    )

    /// The iOS default drive mode: the view's display link paces frames.
    static let displayLink = GhosttyTerminalMetalViewConfiguration(
        isPaused: false,
        enableSetNeedsDisplay: false,
        preferredFramesPerSecond: 60,
        framebufferOnly: true
    )
}

/// The render-session binding shared by both platform hosts: install the
/// session's invalidation handler once, push coalesced snapshots into the
/// renderer, and skip redundant applications by revision.
protocol GhosttyTerminalRenderHost: AnyObject {
    var renderSession: TerminalSurfaceRenderSession? { get set }
    var renderer: GhosttyMetalTerminalRenderer? { get }
    var currentAppearance: TerminalAppearance { get }
    var currentFontSize: CGFloat { get }
    var lastAppliedRenderRevision: UInt64? { get set }
    var lastAppliedAppearance: TerminalAppearance? { get set }
    var lastAppliedFontSize: CGFloat? { get set }
    func requestDraw()
    func updateAccessibilityGridValue(_ surfaceState: TerminalSurfaceState)
}

extension GhosttyTerminalRenderHost {
    func installRenderSessionIfNeeded(_ session: TerminalSurfaceRenderSession) {
        guard renderSession !== session else { return }
        renderSession?.invalidationHandler = nil
        renderSession = session
        lastAppliedRenderRevision = nil
        lastAppliedAppearance = nil
        lastAppliedFontSize = nil
        session.invalidationHandler = { [weak self] in
            self?.applyRenderSessionSnapshot()
        }
    }

    func uninstallRenderSession() {
        renderSession?.invalidationHandler = nil
        renderSession = nil
        lastAppliedRenderRevision = nil
        lastAppliedAppearance = nil
        lastAppliedFontSize = nil
    }

    func applyRenderSessionSnapshot() {
        guard let renderSession,
              let renderer
        else { return }
        let renderInputs = renderSession.renderInputs(
            appearance: currentAppearance,
            fontSize: currentFontSize
        )
        guard lastAppliedRenderRevision != renderInputs.revision ||
            lastAppliedAppearance != renderInputs.appearance ||
            lastAppliedFontSize != renderInputs.fontSize
        else { return }
        renderer.surfaceState = renderInputs.surfaceState
        renderer.frameProjection = renderInputs.frameProjection
        renderer.searchRanges = renderInputs.searchRanges
        renderer.activeSearchRange = renderInputs.activeSearchRange
        renderer.appearance = renderInputs.appearance
        lastAppliedRenderRevision = renderInputs.revision
        lastAppliedAppearance = renderInputs.appearance
        lastAppliedFontSize = renderInputs.fontSize
        MetalSurfaceDiagnostics.recordRenderSnapshotApplied(surface: "terminal")
        updateAccessibilityGridValue(renderInputs.surfaceState)
        requestDraw()
    }
}

#if os(macOS)
    extension GhosttyTerminalHostView: GhosttyTerminalRenderHost {
        var terminalContentRect: CGRect {
            bounds.insetBy(
                dx: TerminalSurfaceDefaults.contentPadding,
                dy: TerminalSurfaceDefaults.contentPadding
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
#endif
