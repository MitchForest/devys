import MetalKit

import AppKit

extension GhosttyTerminalHostView {
    func requestDraw() {
        metalView.needsDisplay = true
        guard window != nil, bounds.isEmpty == false else { return }
        scheduleDrawIfNeeded()
    }

    private func scheduleDrawIfNeeded() {
        guard scheduledDrawTask == nil else { return }

        scheduledDrawTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self else { return }
            self.scheduledDrawTask = nil
            guard self.window != nil, self.bounds.isEmpty == false else { return }
            self.metalView.draw()
        }
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
