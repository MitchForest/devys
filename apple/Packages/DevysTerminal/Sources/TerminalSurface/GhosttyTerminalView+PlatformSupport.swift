// Ported from the reference repo's TerminalSurface host layer (P0-014).
// macOS-only host support: accessibility, backing scale, window resize
// increments, renderer lifecycle, and the compositing-aware MTKView.

#if os(macOS)
    import AppKit
    import MetalKit
    import QuartzCore
    import TerminalSurfaceCore
    import TerminalVT

    private let macTerminalAccessibilityDescription =
        "Supports keyboard input, selection, clipboard, resize, and scrollback. " +
            "Marked-text IME composition and screen-reader cell navigation are not supported."

    extension GhosttyTerminalHostView {
        func configureAccessibility() {
            setAccessibilityElement(true)
            setAccessibilityRole(.textArea)
            setAccessibilityLabel("Terminal")
            setAccessibilityHelp(macTerminalAccessibilityDescription)
        }

        func updateAccessibilityGridValue(_ surfaceState: TerminalSurfaceState) {
            setAccessibilityValue("\(surfaceState.cols) columns by \(surfaceState.rows) rows")
        }

        var currentScaleFactor: CGFloat {
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        }

        func applyWindowResizeIncrements(_ cellSize: CGSize) {
            guard cellSize.width > 0,
                  cellSize.height > 0,
                  window?.contentResizeIncrements != cellSize
            else {
                return
            }
            window?.contentResizeIncrements = cellSize
            MetalSurfaceDiagnostics.recordResizeIncrementsApplied(surface: "terminal")
        }

        func ensureRenderer(fontSize: CGFloat) -> Bool {
            if let renderer, renderer.fontSize == GhosttyTerminalFontMetrics.default(fontSize: fontSize).fontSize {
                metalView.delegate = renderer
                lastRenderFailure = nil
                return true
            }
            if renderer != nil {
                renderer = nil
                metalView.delegate = nil
                lastAppliedRenderRevision = nil
                lastAppliedAppearance = nil
                lastAppliedFontSize = nil
            }

            guard let device = metalView.device else {
                reportRenderFailure("Metal terminal rendering is unavailable on this system.")
                return false
            }

            do {
                let renderer = try GhosttyMetalTerminalRenderer(
                    device: device,
                    scaleFactor: currentScaleFactor,
                    fontSize: fontSize,
                    onFirstAtlasMutation: callbacks.onFirstAtlasMutation,
                    onDrawableUnavailable: { [weak self] in
                        self?.scheduleDrawRetry()
                    },
                    onFirstFrameCommit: callbacks.onFirstFrameCommit,
                    onFirstInteractiveFrame: callbacks.onFirstInteractiveFrame
                )
                self.renderer = renderer
                metalView.delegate = renderer
                lastRenderFailure = nil
                return true
            } catch {
                reportRenderFailure(
                    "Failed to initialize the Metal terminal renderer: \(error.localizedDescription)"
                )
                return false
            }
        }

        func reportRenderFailure(_ message: String) {
            guard lastRenderFailure != message else { return }
            lastRenderFailure = message
            callbacks.onRenderFailure(message)
        }
    }

    final class GlassCapableMTKView: MTKView {
        var drawsOpaqueBackground: Bool {
            didSet {
                applyCompositing()
            }
        }

        override var isOpaque: Bool {
            drawsOpaqueBackground
        }

        init(
            frame frameRect: CGRect,
            device: (any MTLDevice)?,
            drawsOpaqueBackground: Bool = true
        ) {
            self.drawsOpaqueBackground = drawsOpaqueBackground
            super.init(frame: frameRect, device: device)
            wantsLayer = true
            applyCompositing()
        }

        @available(*, unavailable)
        required init(coder _: NSCoder) {
            fatalError("Use init(frame:device:drawsOpaqueBackground:)")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyCompositing()
        }

        func applyCompositing() {
            layer?.isOpaque = drawsOpaqueBackground
            layer?.backgroundColor = drawsOpaqueBackground ? nil : NSColor.clear.cgColor
            if let metalLayer = layer as? CAMetalLayer {
                metalLayer.isOpaque = drawsOpaqueBackground
                metalLayer.wantsExtendedDynamicRangeContent = false
            }
        }
    }

    enum ScrollWheelNormalizer {
        static func pixelDelta(for event: NSEvent, lineHeight: CGFloat) -> CGFloat {
            if event.hasPreciseScrollingDeltas {
                return event.scrollingDeltaY
            }
            return event.deltaY * lineHeight
        }
    }
#endif
