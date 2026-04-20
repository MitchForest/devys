import Foundation
import GhosttyTerminal
import GhosttyTerminalCore

extension HostedLocalTerminalController {
    func report(
        _ checkpoint: TerminalOpenPerformanceTracker.Checkpoint,
        context: [String: String] = [:]
    ) {
        performanceObserver?(checkpoint, context)
    }

    nonisolated static func makeAttachedHandle(
        sessionID: UUID,
        socketPath: String,
        cols: Int,
        rows: Int,
        replayBudget: TerminalHostAttachReplayBudget
    ) throws -> FileHandle {
        let fd = try TerminalHostSocketIO.connect(to: socketPath)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let request = TerminalHostControlRequest.attach(
            sessionID: sessionID,
            cols: cols,
            rows: rows,
            replayBudget: replayBudget
        )
        do {
            try TerminalHostSocketIO.withResponseTimeout(fileDescriptor: fd) {
                let requestData = try JSONEncoder().encode(request)
                try TerminalHostSocketIO.writeLine(requestData, to: handle)

                let responseData = try TerminalHostSocketIO.readLine(from: handle)
                let response = try JSONDecoder().decode(
                    TerminalHostControlResponse.self,
                    from: responseData
                )
                switch response {
                case .attached:
                    return
                case .failure(let message):
                    throw NSError(
                        domain: "HostedLocalTerminalController",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                default:
                    throw TerminalHostSocketError.invalidResponse
                }
            }
            return handle
        } catch {
            try? handle.close()
            throw error
        }
    }

    func attachReplayContext(
        for replayBudget: TerminalHostAttachReplayBudget,
        viewport: HostedTerminalViewport
    ) -> [String: String] {
        [
            "attach_replay_mode": replayBudget.recentOutputBytes > 0 ? "recent_output" : "none",
            "attach_replay_bytes": String(replayBudget.recentOutputBytes),
            "cols": String(viewport.size.cols),
            "rows": String(viewport.size.rows)
        ]
    }

    func viewportContext(for viewport: HostedTerminalViewport) -> [String: String] {
        [
            "cols": String(viewport.size.cols),
            "rows": String(viewport.size.rows),
            "cell_width_px": String(viewport.cellWidthPx),
            "cell_height_px": String(viewport.cellHeightPx)
        ]
    }

    func dirtyKindName(_ dirtyKind: GhosttyTerminalDirtyKind) -> String {
        switch dirtyKind {
        case .clean:
            "clean"
        case .partial:
            "partial"
        case .full:
            "full"
        }
    }

    func applySelection(_ selectionRange: GhosttyTerminalSelectionRange?) {
        surfaceState = surfaceState.withSelection(selectionRange)
        frameProjection = projectionBuilder.applySelection(selectionRange, to: frameProjection)
    }

    func attachReplayBudget() -> TerminalHostAttachReplayBudget {
        hasReportedFirstSurfaceUpdate
            ? .none
            : .hostedTerminalDefault
    }

    func applyLocalViewportDimensions(_ size: HostedTerminalViewportSize) {
        surfaceState.cols = size.cols
        surfaceState.rows = size.rows
        frameProjection.cols = size.cols
        frameProjection.rows = size.rows
    }

    func initializeRuntimeIfNeeded(for viewport: HostedTerminalViewport) -> Bool {
        guard runtime == nil else { return true }

        do {
            runtime = try GhosttyVTRuntime(
                cols: viewport.size.cols,
                rows: viewport.size.rows,
                scrollbackMax: scrollbackMax,
                appearance: appearance
            )
        } catch {
            failStartup(message: "Failed to initialize the terminal runtime: \(error.localizedDescription)")
            return false
        }

        return true
    }

    func resumeViewportContinuations(with viewport: HostedTerminalViewport) {
        guard !viewportContinuations.isEmpty else { return }
        let continuations = viewportContinuations
        viewportContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(returning: viewport)
        }
    }

    func cancelViewportWaiters() {
        guard !viewportContinuations.isEmpty else { return }
        let continuations = viewportContinuations
        viewportContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }

}

func terminalHostResizePayload(for size: HostedTerminalViewportSize) -> Data? {
    try? JSONEncoder().encode(
        TerminalHostResizeFrame(cols: size.cols, rows: size.rows)
    )
}
