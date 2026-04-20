import GhosttyTerminalCore

#if os(macOS)
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

    func ensureRenderer() -> Bool {
        if let renderer {
            metalView.delegate = renderer
            lastRenderFailure = nil
            return true
        }

        guard let device = metalView.device else {
            reportRenderFailure("Metal terminal rendering is unavailable on this system.")
            return false
        }

        do {
            let renderer = try GhosttyMetalTerminalRenderer(
                device: device,
                scaleFactor: currentScaleFactor,
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
#elseif os(iOS)
import UIKit

private let iosTerminalAccessibilityHint =
    "Supports keyboard input, selection, clipboard, resize, and scrollback. " +
    "Marked-text IME composition and screen-reader cell navigation are not supported."

extension GhosttyTerminalHostView {
    func configureAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = [.allowsDirectInteraction]
        accessibilityLabel = "Terminal"
        accessibilityHint = iosTerminalAccessibilityHint
    }

    func updateAccessibilityValue(for surfaceState: GhosttyTerminalSurfaceState) {
        accessibilityValue = "\(surfaceState.cols) columns by \(surfaceState.rows) rows"
    }

    var currentScaleFactor: CGFloat {
        window?.screen.scale ?? UIScreen.main.scale
    }

    func ensureRenderer() -> Bool {
        if let renderer {
            metalView.delegate = renderer
            lastRenderFailure = nil
            return true
        }

        guard let device = metalView.device else {
            reportRenderFailure("Metal terminal rendering is unavailable on this system.")
            return false
        }

        do {
            let renderer = try GhosttyMetalTerminalRenderer(
                device: device,
                scaleFactor: currentScaleFactor,
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
#endif
