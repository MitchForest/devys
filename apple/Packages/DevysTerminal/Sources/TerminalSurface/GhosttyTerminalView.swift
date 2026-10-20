// Ported from the reference repo's TerminalSurface host layer (P0-014).
// The SwiftUI facade is cross-platform; the NSView host below is the
// macOS port (keyboard/IME-lite input, selection, clipboard, resize
// increments, accessibility). The iOS host is net-new in
// GhosttyTerminalIOSHostView.swift - the reference had no iOS host.

import Foundation
import MetalKit
import SwiftUI
import TerminalSurfaceCore
import TerminalVT

#if os(macOS)
    import AppKit
#endif

struct GhosttyTerminalView: View {
    let renderSession: TerminalSurfaceRenderSession
    let appearance: TerminalAppearance
    let fontSize: CGFloat
    let selectionMode: Bool
    let focusRequestID: Int
    let isSurfaceVisible: Bool

    let callbacks: GhosttyTerminalViewCallbacks
}

#if os(macOS)
    struct GhosttyTerminalMacPlatformView: NSViewRepresentable {
        let renderSession: TerminalSurfaceRenderSession
        let appearance: TerminalAppearance
        let fontSize: CGFloat
        let selectionMode: Bool
        let focusRequestID: Int
        let isSurfaceVisible: Bool
        let targetPointSize: CGSize
        let callbacks: GhosttyTerminalViewCallbacks

        func makeNSView(context _: Context) -> GhosttyTerminalHostView {
            GhosttyTerminalHostView()
        }

        func updateNSView(_ nsView: GhosttyTerminalHostView, context _: Context) {
            nsView.update(viewUpdate, callbacks: callbacks)
        }

        private var viewUpdate: GhosttyTerminalViewUpdate {
            GhosttyTerminalViewUpdate(
                renderSession: renderSession,
                appearance: appearance,
                fontSize: fontSize,
                selectionMode: selectionMode,
                focusRequestID: focusRequestID,
                isSurfaceVisible: isSurfaceVisible,
                targetPointSize: targetPointSize
            )
        }

        static func dismantleNSView(_ nsView: GhosttyTerminalHostView, coordinator _: ()) {
            nsView.uninstallRenderSession()
        }
    }

    final class GhosttyTerminalHostView: NSView {
        let metalView = GlassCapableMTKView(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice(),
            drawsOpaqueBackground: false
        )
        var renderer: GhosttyMetalTerminalRenderer?
        weak var renderSession: TerminalSurfaceRenderSession?
        let drawScheduler = MetalDrawScheduler(surface: "terminal")
        var callbacks = GhosttyTerminalViewCallbacks()
        var currentAppearance = TerminalAppearance.defaultDark
        var currentFontSize: CGFloat = 13
        private var focusRequestID = 0
        private var lastHandledFocusRequestID = 0
        private var selectionMode = true
        private var dragAnchor: CGPoint?
        private var isSelectionDragActive = false
        var lastAppliedRenderRevision: UInt64?
        var lastAppliedAppearance: TerminalAppearance?
        var lastAppliedFontSize: CGFloat?
        private var scrollAccumulator = TerminalScrollAccumulator()
        var markedText = NSMutableAttributedString()
        var keyTextAccumulator: [String]?
        var lastRenderFailure: String?
        private var targetPointSize = CGSize.zero
        private var lastSurfaceSize: TerminalSurfacePixelSize?

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        init() {
            super.init(frame: .zero)
            MetalSurfaceDiagnostics.recordHostCreated(surface: "terminal")
            wantsLayer = true
            layer?.isOpaque = false
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.masksToBounds = true
            configureMetalView()
            configureAccessibility()
            addSubview(metalView)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        isolated deinit {
            MetalSurfaceDiagnostics.recordHostDeinitialized(surface: "terminal")
        }

        func update(_ update: GhosttyTerminalViewUpdate, callbacks: GhosttyTerminalViewCallbacks) {
            self.callbacks = callbacks
            selectionMode = update.selectionMode
            focusRequestID = update.focusRequestID
            currentAppearance = update.appearance
            currentFontSize = update.fontSize
            targetPointSize = update.targetPointSize
            metalView.isHidden = !update.isSurfaceVisible
            drawScheduler.setVisible(update.isSurfaceVisible)
            installRenderSessionIfNeeded(update.renderSession)

            guard ensureRenderer(fontSize: update.fontSize) else {
                updateAccessibilityGridValue(update.renderSession.surfaceState)
                return
            }

            applyRenderSessionSnapshot()
            updateAccessibilityGridValue(update.renderSession.surfaceState)
            synchronizeHostedGeometry()
            applyFocusRequestIfNeeded()
        }

        override func layout() {
            super.layout()
            synchronizeHostedGeometry()
            requestImmediateDraw()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            synchronizeHostedGeometry()
            applyFocusRequestIfNeeded()
            requestImmediateDraw()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            synchronizeHostedGeometry()
            requestImmediateDraw()
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
                    callbacks.onInput(TerminalMacInputAdapter.commandPaste(text))
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

            let markedTextBefore = hasMarkedText()
            keyTextAccumulator = []
            interpretKeyEvents([event])
            let committedText = keyTextAccumulator ?? []
            keyTextAccumulator = nil

            let composing = hasMarkedText() || markedTextBefore
            if !committedText.isEmpty {
                for text in committedText where !Self.shouldSuppressComposingControlInput(text, composing: composing) {
                    if let command = TerminalMacInputAdapter.command(for: event, text: text) {
                        callbacks.onInput(command)
                    }
                }
                return
            }

            guard composing == false else { return }
            guard !Self.shouldSuppressComposingControlInput(event.characters, composing: composing),
                  let command = TerminalMacInputAdapter.command(for: event) else {
                super.keyDown(with: event)
                return
            }
            callbacks.onInput(command)
        }

        override func keyUp(with event: NSEvent) {
            if let command = TerminalMacInputAdapter.keyUpCommand(for: event) {
                callbacks.onInput(command)
            }
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

        override func mouseUp(with _: NSEvent) {
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
            MetalSurfaceDiagnostics.recordScrollEventReceived(surface: "terminal")
            if event.phase == .ended ||
                event.phase == .cancelled ||
                event.momentumPhase == .ended ||
                event.momentumPhase == .cancelled {
                scrollAccumulator.reset()
                return
            }
            let lineHeight = max(renderer.pointCellSize.height, 1)
            let pixelDelta = -ScrollWheelNormalizer.pixelDelta(for: event, lineHeight: lineHeight)
            let lines = scrollAccumulator.appendPixelDelta(pixelDelta, lineHeight: lineHeight)
            guard lines != 0 else { return }
            MetalSurfaceDiagnostics.recordScrollLinesEmitted(lines, surface: "terminal")
            callbacks.onScroll(scrollEvent(lines: lines, event: event, renderer: renderer))
        }

        override func magnify(with _: NSEvent) {}

        private func configureMetalView() {
            let configuration = GhosttyTerminalMetalViewConfiguration.onDemand
            drawScheduler.attach(metalView)
            metalView.colorPixelFormat = .bgra8Unorm_srgb
            metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            metalView.applyCompositing()
            metalView.isPaused = configuration.isPaused
            metalView.enableSetNeedsDisplay = configuration.enableSetNeedsDisplay
            metalView.preferredFramesPerSecond = configuration.preferredFramesPerSecond
            metalView.framebufferOnly = configuration.framebufferOnly
            metalView.autoresizingMask = [.width, .height]
        }

        func synchronizeHostedGeometry() {
            guard bounds.width > 1, bounds.height > 1 else { return }
            let targetFrame = terminalContentRect
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if metalView.frame != targetFrame {
                metalView.frame = targetFrame
                MetalSurfaceDiagnostics.recordHostFrameChanged(surface: "terminal")
            }
            metalView.layer?.masksToBounds = true
            if let window {
                let scale = window.backingScaleFactor
                layer?.contentsScale = scale
                metalView.layer?.contentsScale = scale
                let backingSize = convertToBacking(NSRect(origin: .zero, size: targetFrame.size)).size
                let drawableSize = CGSize(
                    width: floor(max(1, backingSize.width)),
                    height: floor(max(1, backingSize.height))
                )
                if metalView.drawableSize != drawableSize {
                    metalView.drawableSize = drawableSize
                    MetalSurfaceDiagnostics.recordDrawableSizeChanged(surface: "terminal")
                }
            }
            CATransaction.commit()
            notifySurfaceSizeIfNeeded(targetFrame: targetFrame)
        }

        func gridMetrics() -> GhosttyTerminalGridMetrics? {
            guard let renderer else { return nil }
            return GhosttyTerminalGridMetrics(
                cols: max(1, renderer.surfaceState.cols),
                rows: max(1, renderer.surfaceState.rows),
                cellWidth: renderer.pointCellSize.width,
                cellHeight: renderer.pointCellSize.height
            )
        }

        private func scrollEvent(
            lines: Int,
            event: NSEvent,
            renderer: GhosttyMetalTerminalRenderer
        ) -> TerminalSurfaceScrollEvent {
            let contentPoint = terminalContentPoint(
                from: convert(event.locationInWindow, from: nil)
            )
            let scale = currentScaleFactor
            let contentSize = terminalContentRect.size
            return TerminalSurfaceScrollEvent(
                lines: lines,
                positionX: Float(max(0, contentPoint.x * scale)),
                positionY: Float(max(0, contentPoint.y * scale)),
                screenWidthPx: UInt32(max(1, Int((contentSize.width * scale).rounded()))),
                screenHeightPx: UInt32(max(1, Int((contentSize.height * scale).rounded()))),
                cellWidthPx: UInt32(max(1, Int((renderer.pointCellSize.width * scale).rounded()))),
                cellHeightPx: UInt32(max(1, Int((renderer.pointCellSize.height * scale).rounded())))
            )
        }

        private func notifySurfaceSizeIfNeeded(targetFrame: CGRect) {
            guard let renderer,
                  targetPointSize.width > 1,
                  targetPointSize.height > 1,
                  !targetFrame.isEmpty
            else { return }
            let cellSize = renderer.pointCellSize
            applyWindowResizeIncrements(cellSize)
            let contentPointSize = CGSize(
                width: max(1, targetPointSize.width - TerminalSurfaceDefaults.contentPadding * 2),
                height: max(1, targetPointSize.height - TerminalSurfaceDefaults.contentPadding * 2)
            )
            let backingSize = convertToBacking(NSRect(origin: .zero, size: contentPointSize)).size
            let surfaceSize = TerminalSurfacePixelSize(
                pixelWidth: Int(floor(max(1, backingSize.width))),
                pixelHeight: Int(floor(max(1, backingSize.height))),
                scale: currentScaleFactor,
                cellWidthPoints: cellSize.width,
                cellHeightPoints: cellSize.height
            )
            guard surfaceSize != lastSurfaceSize else { return }
            lastSurfaceSize = surfaceSize
            MetalSurfaceDiagnostics.recordViewportRequested(surface: "terminal")
            callbacks.onSurfaceSizeChange(surfaceSize)
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
    }
#endif
