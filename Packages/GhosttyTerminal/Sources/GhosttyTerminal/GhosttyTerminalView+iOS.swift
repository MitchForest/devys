import Foundation
import MetalKit
import SwiftUI

#if os(iOS)
// periphery:ignore:import needed for iOS-only Ghostty terminal surface types
import GhosttyTerminalCore
import UIKit

struct GhosttyTerminalPlatformView: UIViewRepresentable {
    let surfaceState: GhosttyTerminalSurfaceState
    let frameProjection: GhosttyTerminalFrameProjection
    let appearance: GhosttyTerminalAppearance
    let selectionMode: Bool
    let focusRequestID: Int
    let callbacks: GhosttyTerminalViewCallbacks

    func makeUIView(context: Context) -> GhosttyTerminalHostView {
        let view = GhosttyTerminalHostView()
        view.update(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            selectionMode: selectionMode,
            callbacks: callbacks
        )
        return view
    }

    func updateUIView(_ uiView: GhosttyTerminalHostView, context: Context) {
        uiView.update(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            selectionMode: selectionMode,
            callbacks: callbacks
        )
    }
}

@MainActor
final class GhosttyTerminalHostView: UIView {
    let metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    var renderer: GhosttyMetalTerminalRenderer?
    var callbacks = GhosttyTerminalViewCallbacks()
    private var selectionMode = false
    private var hasStartedSelectionDrag = false
    private var lastViewportSignature = ""
    private var lastRenderInputs: GhosttyTerminalRenderInputs?
    var drawRetryTask: Task<Void, Never>?
    var lastRenderFailure: String?

    init() {
        super.init(frame: .zero)
        configureMetalView()
        configureAccessibility()
        addSubview(metalView)
        installGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        drawRetryTask?.cancel()
    }

    func update(
        surfaceState: GhosttyTerminalSurfaceState,
        frameProjection: GhosttyTerminalFrameProjection,
        appearance: GhosttyTerminalAppearance,
        selectionMode: Bool,
        callbacks: GhosttyTerminalViewCallbacks
    ) {
        self.callbacks = callbacks
        self.selectionMode = selectionMode
        let renderInputs = GhosttyTerminalRenderInputs(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance
        )

        guard ensureRenderer() else {
            updateAccessibilityValue(for: surfaceState)
            return
        }

        if lastRenderInputs != renderInputs {
            renderer?.surfaceState = surfaceState
            renderer?.frameProjection = frameProjection
            renderer?.appearance = appearance
            lastRenderInputs = renderInputs
            requestDraw()
        }
        updateAccessibilityValue(for: surfaceState)
        notifyViewportIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView.frame = bounds
        notifyViewportIfNeeded()
        requestDraw()
    }

    private func configureMetalView() {
        let configuration = GhosttyTerminalMetalViewConfiguration.onDemand
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.isPaused = configuration.isPaused
        metalView.enableSetNeedsDisplay = configuration.enableSetNeedsDisplay
        metalView.preferredFramesPerSecond = configuration.preferredFramesPerSecond
        metalView.framebufferOnly = configuration.framebufferOnly
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.isUserInteractionEnabled = false
        clipsToBounds = true
    }

    private func installGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            callbacks.onTap()
            if selectionMode == false {
                callbacks.onClearSelection()
            }
        }
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let grid = gridMetrics() else { return }
        let point = recognizer.location(in: self)
        let cell = grid.clampedCell(for: point)
        callbacks.onSelectWord(cell.row, cell.col)
        callbacks.onTap()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let grid = gridMetrics() else { return }

        if selectionMode {
            let point = recognizer.location(in: self)
            let cell = grid.clampedCell(for: point)
            switch recognizer.state {
            case .began:
                hasStartedSelectionDrag = true
                callbacks.onSelectionBegin(cell.row, cell.col)
            case .changed:
                if hasStartedSelectionDrag == false {
                    hasStartedSelectionDrag = true
                    callbacks.onSelectionBegin(cell.row, cell.col)
                } else {
                    callbacks.onSelectionMove(cell.row, cell.col)
                }
            case .ended, .cancelled, .failed:
                if hasStartedSelectionDrag {
                    callbacks.onSelectionEnd()
                }
                hasStartedSelectionDrag = false
            default:
                break
            }
            return
        }

        if recognizer.state == .ended {
            let rawLines = -recognizer.translation(in: self).y / max(grid.cellHeight, 1)
            let lines = Int(rawLines.rounded())
            if lines != 0 {
                callbacks.onScroll(lines)
            }
        }
    }

    private func gridMetrics() -> GhosttyTerminalGridMetrics? {
        guard let renderer else { return nil }
        return GhosttyTerminalGridMetrics(
            cols: max(1, renderer.surfaceState.cols),
            rows: max(1, renderer.surfaceState.rows),
            cellWidth: renderer.pointCellSize.width,
            cellHeight: renderer.pointCellSize.height
        )
    }

    private func notifyViewportIfNeeded() {
        guard let renderer, !bounds.isEmpty else { return }
        let cellSize = renderer.pointCellSize
        let cols = max(20, Int(floor(bounds.width / max(cellSize.width, 1))))
        let rows = max(5, Int(floor(bounds.height / max(cellSize.height, 1))))
        let cellWidthPx = max(1, Int((cellSize.width * currentScaleFactor).rounded()))
        let cellHeightPx = max(1, Int((cellSize.height * currentScaleFactor).rounded()))
        let signature = "\(bounds.size.width)x\(bounds.size.height)|\(cols)x\(rows)|\(cellWidthPx)x\(cellHeightPx)"
        guard signature != lastViewportSignature else { return }
        lastViewportSignature = signature
        requestDraw()
        callbacks.onViewportSizeChange(bounds.size, cols, rows, cellWidthPx, cellHeightPx)
    }
}
#endif
