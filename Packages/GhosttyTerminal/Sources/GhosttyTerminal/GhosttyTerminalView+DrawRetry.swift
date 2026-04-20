import MetalKit

#if os(macOS)
import AppKit

extension GhosttyTerminalHostView {
    func requestDraw() {
        metalView.needsDisplay = true
        guard window != nil, bounds.isEmpty == false else { return }
        metalView.draw()
    }

    func scheduleDrawRetry() {
        guard drawRetryTask == nil else { return }

        drawRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self else { return }
            self.drawRetryTask = nil
            self.requestDraw()
        }
    }
}
#elseif os(iOS)
import UIKit

extension GhosttyTerminalHostView {
    func requestDraw() {
        metalView.setNeedsDisplay()
        guard window != nil, bounds.isEmpty == false else { return }
        metalView.draw()
    }

    func scheduleDrawRetry() {
        guard drawRetryTask == nil else { return }

        drawRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self else { return }
            self.drawRetryTask = nil
            self.requestDraw()
        }
    }
}
#endif
