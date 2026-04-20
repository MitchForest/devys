import Foundation
import GhosttyTerminal

enum TerminalSessionStartupLifecycle {
    static func phaseAfterHostReady(
        viewportReady: Bool
    ) -> GhosttyTerminalStartupPhase {
        viewportReady ? .startingShell : .awaitingViewport
    }

    static func phaseAfterFirstSurfaceUpdate(
        from currentPhase: GhosttyTerminalStartupPhase
    ) -> GhosttyTerminalStartupPhase {
        currentPhase
    }

    static func phaseAfterFirstRenderableFrame(
        from currentPhase: GhosttyTerminalStartupPhase,
        hasSurfaceUpdate: Bool,
        hasInteractiveFrame: Bool,
        hasOutputChunk: Bool
    ) -> GhosttyTerminalStartupPhase {
        guard hasSurfaceUpdate, hasInteractiveFrame, hasOutputChunk else {
            return currentPhase
        }

        switch currentPhase {
        case .startingShell:
            return .ready
        case .startingHost, .awaitingViewport, .ready, .failed:
            return currentPhase
        }
    }

    static func phaseAfterClose(
        from currentPhase: GhosttyTerminalStartupPhase
    ) -> GhosttyTerminalStartupPhase {
        currentPhase == .ready ? .ready : .failed
    }

    static func closeDescription(
        exitCode: Int?,
        signal: String?,
        startupPhase: GhosttyTerminalStartupPhase
    ) -> String? {
        if let exitCode, exitCode != 0 {
            return "Shell exited with status \(exitCode)."
        }
        if let signal {
            return "Shell terminated by signal \(signal)."
        }
        if startupPhase != .ready {
            return "Shell exited before the first frame arrived."
        }
        return nil
    }
}
