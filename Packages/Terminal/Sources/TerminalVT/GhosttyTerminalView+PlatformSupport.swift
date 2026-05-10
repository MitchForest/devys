import AppKit

private let macTerminalAccessibilityHelp =
    "Supports keyboard input, selection, clipboard, resize, and scrollback. " +
    "Marked-text IME composition and screen-reader cell navigation are not supported."

extension GhosttyTerminalHostView {
    func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Terminal")
        setAccessibilityHelp(macTerminalAccessibilityHelp)
    }

    func updateAccessibilityValue(for surfaceState: GhosttyTerminalSurfaceState) {
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
            lastRenderInputs = nil
            lastViewportSignature = ""
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
