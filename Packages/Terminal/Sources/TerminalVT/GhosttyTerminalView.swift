import Foundation
import MetalKit
import Rendering
import SwiftUI

import AppKit

public struct GhosttyTerminalView: View {
    public let surfaceState: GhosttyTerminalSurfaceState
    public let frameProjection: GhosttyTerminalFrameProjection
    public let appearance: GhosttyTerminalAppearance
    public let fontSize: CGFloat
    public let selectionMode: Bool
    public let focusRequestID: Int

    let callbacks: GhosttyTerminalViewCallbacks
}

struct GhosttyTerminalPlatformView: NSViewRepresentable {
    let surfaceState: GhosttyTerminalSurfaceState
    let frameProjection: GhosttyTerminalFrameProjection
    let appearance: GhosttyTerminalAppearance
    let fontSize: CGFloat
    let selectionMode: Bool
    let focusRequestID: Int
    let callbacks: GhosttyTerminalViewCallbacks

    func makeNSView(context: Context) -> GhosttyTerminalHostView {
        let view = GhosttyTerminalHostView()
        view.update(viewUpdate, callbacks: callbacks)
        return view
    }

    func updateNSView(_ nsView: GhosttyTerminalHostView, context: Context) {
        nsView.update(viewUpdate, callbacks: callbacks)
    }

    private var viewUpdate: GhosttyTerminalViewUpdate {
        GhosttyTerminalViewUpdate(
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            appearance: appearance,
            fontSize: fontSize,
            selectionMode: selectionMode,
            focusRequestID: focusRequestID
        )
    }
}

@MainActor
final class GhosttyTerminalHostView: NSView {
    let metalView = GlassCapableMTKView(
        frame: .zero,
        device: MTLCreateSystemDefaultDevice(),
        drawsOpaqueBackground: false
    )
    var renderer: GhosttyMetalTerminalRenderer?
    var callbacks = GhosttyTerminalViewCallbacks()
    private var focusRequestID = 0
    private var lastHandledFocusRequestID = 0
    private var selectionMode = true
    private var dragAnchor: CGPoint?
    private var isSelectionDragActive = false
    var lastViewportSignature = ""
    var lastRenderInputs: GhosttyTerminalRenderInputs?
    var drawRetryTask: Task<Void, Never>?
    var scheduledDrawTask: Task<Void, Never>?
    var lastRenderFailure: String?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = .clear
        configureMetalView()
        configureAccessibility()
        addSubview(metalView)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        drawRetryTask?.cancel()
        scheduledDrawTask?.cancel()
    }

    func update(_ update: GhosttyTerminalViewUpdate, callbacks: GhosttyTerminalViewCallbacks) {
        self.callbacks = callbacks
        selectionMode = update.selectionMode
        focusRequestID = update.focusRequestID
        let renderInputs = update.renderInputs

        guard ensureRenderer(fontSize: update.fontSize) else {
            updateAccessibilityValue(for: update.surfaceState)
            return
        }

        if lastRenderInputs != renderInputs {
            renderer?.surfaceState = update.surfaceState
            renderer?.frameProjection = update.frameProjection
            renderer?.appearance = update.appearance
            lastRenderInputs = renderInputs
            requestDraw()
        }
        updateAccessibilityValue(for: update.surfaceState)
        notifyViewportIfNeeded()
        applyFocusRequestIfNeeded()
    }

    override func layout() {
        super.layout()
        metalView.frame = terminalContentRect
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
            let cell = grid.clampedCell(for: terminalContentPoint(from: point))
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
            let start = grid.clampedCell(for: terminalContentPoint(from: anchor))
            callbacks.onSelectionBegin(start.row, start.col)
            isSelectionDragActive = true
        }
        guard isSelectionDragActive else { return }
        let cell = grid.clampedCell(for: terminalContentPoint(from: point))
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
        // Default to transparent backing so the window vibrancy shows through any
        // area not painted by an opaque cell. The renderer overrides clearColor
        // and layer opacity to match the active appearance once attached.
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // GlassCapableMTKView overrides isOpaque so AppKit knows to redraw what's
        // behind. The underlying CAMetalLayer must also be non-opaque for the
        // alpha channel to actually composite against the window backing.
        metalView.applyCompositing()
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
        guard let renderer, !terminalContentRect.isEmpty else { return }
        let cellSize = renderer.pointCellSize
        applyWindowResizeIncrements(cellSize)
        let contentSize = terminalContentRect.size
        let cols = max(20, Int(floor(contentSize.width / max(cellSize.width, 1))))
        let rows = max(5, Int(floor(contentSize.height / max(cellSize.height, 1))))
        let cellWidthPx = max(1, Int((cellSize.width * currentScaleFactor).rounded()))
        let cellHeightPx = max(1, Int((cellSize.height * currentScaleFactor).rounded()))
        let signature = "\(cols)x\(rows)|\(cellWidthPx)x\(cellHeightPx)"
        guard signature != lastViewportSignature else { return }
        lastViewportSignature = signature
        callbacks.onViewportSizeChange(contentSize, cols, rows, cellWidthPx, cellHeightPx)
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
