// Ported from the reference repo's TerminalSurface host layer (P0-014).

import MetalKit
import TerminalSurfaceCore

#if os(macOS)
    extension GhosttyTerminalHostView {
        func requestDraw() {
            drawScheduler.requestDraw()
        }

        func requestImmediateDraw() {
            drawScheduler.requestImmediateDraw()
        }

        func scheduleDrawRetry() {
            drawScheduler.requestRetry()
        }
    }
#endif
