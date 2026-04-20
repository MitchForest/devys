import Foundation
import GhosttyTerminalCore
import MetalKit
import Rendering
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct GhosttyTerminalView: View {
    public let surfaceState: GhosttyTerminalSurfaceState
    public let frameProjection: GhosttyTerminalFrameProjection
    public let appearance: GhosttyTerminalAppearance
    public let selectionMode: Bool
    public let focusRequestID: Int

    let callbacks: GhosttyTerminalViewCallbacks
}

#if os(macOS)
struct GhosttyTerminalPlatformView: NSViewRepresentable {
    let surfaceState: GhosttyTerminalSurfaceState
    let frameProjection: GhosttyTerminalFrameProjection
    let appearance: GhosttyTerminalAppearance
    let selectionMode: Bool
    let focusRequestID: Int
    let callbacks: GhosttyTerminalViewCallbacks

    func makeNSView(context: Context) -> GhosttyTerminalHostView {
        let view = GhosttyTerminalHostView()
        view.update(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            selectionMode: selectionMode,
            focusRequestID: focusRequestID,
            callbacks: callbacks
        )
        return view
    }

    func updateNSView(_ nsView: GhosttyTerminalHostView, context: Context) {
        nsView.update(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            selectionMode: selectionMode,
            focusRequestID: focusRequestID,
            callbacks: callbacks
        )
    }
}

@MainActor
final class GhosttyTerminalHostView: NSView {
    let metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    var renderer: GhosttyMetalTerminalRenderer?
    var callbacks = GhosttyTerminalViewCallbacks()
    private var focusRequestID = 0
    private var lastHandledFocusRequestID = 0
    private var selectionMode = true
    private var dragAnchor: CGPoint?
    private var isSelectionDragActive = false
    private var lastViewportSignature = ""
    private var lastRenderInputs: GhosttyTerminalRenderInputs?
    var drawRetryTask: Task<Void, Never>?
    var lastRenderFailure: String?

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        configureMetalView()
        configureAccessibility()
        addSubview(metalView)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
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
        focusRequestID: Int,
        callbacks: GhosttyTerminalViewCallbacks
    ) {
        self.callbacks = callbacks
        self.selectionMode = selectionMode
        self.focusRequestID = focusRequestID
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
        applyFocusRequestIfNeeded()
    }

    override func layout() {
        super.layout()
        metalView.frame = bounds
        notifyViewportIfNeeded()
        requestDraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyViewportIfNeeded()
        applyFocusRequestIfNeeded()
        requestDraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        notifyViewportIfNeeded()
        requestDraw()
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])

        if modifiers.contains(.command) {
            if event.charactersIgnoringModifiers == "v",
               let text = NSPasteboard.general.string(forType: .string),
               !text.isEmpty {
                callbacks.onPasteText(text)
                return
            }

            if event.charactersIgnoringModifiers == "c",
               let selection = callbacks.selectionTextProvider(),
               !selection.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selection, forType: .string)
                return
            }

            super.keyDown(with: event)
            return
        }

        if let specialKey = specialKey(for: event) {
            callbacks.onSendSpecialKey(specialKey)
            return
        }

        if modifiers.contains(.control),
           let character = event.charactersIgnoringModifiers?.first {
            if modifiers.contains(.option),
               let altText = event.charactersIgnoringModifiers,
               !altText.isEmpty {
                callbacks.onSendAltText(altText)
            }
            callbacks.onSendControlCharacter(character)
            return
        }

        if modifiers.contains(.option),
           let altText = event.charactersIgnoringModifiers,
           !altText.isEmpty {
            callbacks.onSendAltText(altText)
            return
        }

        if let text = event.characters, !text.isEmpty {
            callbacks.onSendText(text)
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        callbacks.onTap()

        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let grid = gridMetrics() {
            let cell = grid.clampedCell(for: point)
            callbacks.onSelectWord(cell.row, cell.col)
            return
        }

        dragAnchor = point
        isSelectionDragActive = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionMode, let anchor = dragAnchor, let grid = gridMetrics() else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - anchor.x, point.y - anchor.y)
        if isSelectionDragActive == false, distance > 2 {
            let start = grid.clampedCell(for: anchor)
            callbacks.onSelectionBegin(start.row, start.col)
            isSelectionDragActive = true
        }
        guard isSelectionDragActive else { return }
        let cell = grid.clampedCell(for: point)
        callbacks.onSelectionMove(cell.row, cell.col)
    }

    override func mouseUp(with event: NSEvent) {
        if isSelectionDragActive {
            callbacks.onSelectionEnd()
        } else {
            callbacks.onClearSelection()
        }
        dragAnchor = nil
        isSelectionDragActive = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard let renderer else { return }
        let lineHeight = max(renderer.pointCellSize.height, 1)
        let rawLines = -ScrollWheelNormalizer.pixelDelta(for: event, lineHeight: lineHeight) / lineHeight
        let lines = Int(rawLines.rounded())
        guard lines != 0 else { return }
        callbacks.onScroll(lines)
    }

    override func magnify(with event: NSEvent) {}

    private func configureMetalView() {
        let configuration = GhosttyTerminalMetalViewConfiguration.onDemand
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.isPaused = configuration.isPaused
        metalView.enableSetNeedsDisplay = configuration.enableSetNeedsDisplay
        metalView.preferredFramesPerSecond = configuration.preferredFramesPerSecond
        metalView.framebufferOnly = configuration.framebufferOnly
        metalView.autoresizingMask = [.width, .height]
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
        callbacks.onViewportSizeChange(bounds.size, cols, rows, cellWidthPx, cellHeightPx)
    }

    private func applyFocusRequestIfNeeded() {
        guard focusRequestID != lastHandledFocusRequestID,
              let window
        else { return }
        window.makeFirstResponder(self)
        if window.firstResponder === self {
            lastHandledFocusRequestID = focusRequestID
        }
    }

    private func specialKey(for event: NSEvent) -> GhosttyTerminalSpecialKey? {
        switch Int(event.keyCode) {
        case 36, 76:
            return .enter
        case 48:
            return event.modifierFlags.contains(.shift) ? .backtab : .tab
        case 51:
            return .backspace
        case 117:
            return .delete
        case 53:
            return .escape
        case 123:
            return .left
        case 124:
            return .right
        case 125:
            return .down
        case 126:
            return .up
        case 115:
            return .home
        case 119:
            return .end
        case 116:
            return .pageUp
        case 121:
            return .pageDown
        default:
            return nil
        }
    }
}
#endif
