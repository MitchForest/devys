import Foundation
import SwiftUI

extension IOSClientConnectionStore {
    func updateTerminalViewport(size: CGSize) {
        guard let estimated = estimateGridSize(for: size) else { return }
        preferredTerminalCols = estimated.cols
        preferredTerminalRows = estimated.rows
        lastAppliedViewportGrid = estimated

        guard sshTerminalSession.sessionID != nil else { return }
        guard isTerminalActivelyConnected else { return }
        guard sshTerminalSession.cols != estimated.cols || sshTerminalSession.rows != estimated.rows else { return }

        pendingViewportResizeTask?.cancel()
        pendingViewportResizeTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 160_000_000)
            if Task.isCancelled { return }

            guard let latestGrid = self.lastAppliedViewportGrid else { return }
            guard latestGrid.cols == estimated.cols, latestGrid.rows == estimated.rows else { return }

            do {
                try await self.sshTerminalSession.resize(cols: estimated.cols, rows: estimated.rows, source: .window)
                persistResumeSnapshot()
            } catch {
                state = .failed("Terminal resize failed: \(error.localizedDescription)")
            }
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            shouldResumeOnActive = setupAutoResumeLastSession && isTerminalActivelyConnected
            sshTerminalSession.suspend()
            persistResumeSnapshot()
        case .active:
            let shouldAttemptResume = shouldResumeOnActive
            shouldResumeOnActive = false
            if shouldAttemptResume, sshTerminalSession.sessionID != nil {
                reconnectSSHSession()
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func reconcileSelectionAfterSessionRefresh() {
        if sessions.isEmpty {
            selectedSessionID = nil
            if launchMode == .attachExisting {
                launchMode = .newSession
            }
            return
        }

        if launchMode == .attachExisting {
            if let selectedSessionID,
               sessions.contains(where: { $0.id == selectedSessionID }) {
                return
            }
            selectedSessionID = sessions.first?.id
            return
        }

        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) == false {
            self.selectedSessionID = nil
        }
    }

    func attemptTerminalReconnect(mode: ReconnectMode) async {
        let maxAttempts = 3
        var delay: UInt64 = 400_000_000
        let reconnectStartedAt = Date()
        readinessTelemetry.reconnectAttempts += 1
        readinessTelemetry.lastUpdatedAt = Date()

        for attempt in 1...maxAttempts {
            reconnectAttemptMessage = "reconnect attempt \(attempt)/\(maxAttempts)"

            do {
                switch mode {
                case .manualReconnect:
                    try await sshTerminalSession.reconnect()
                case .resumeIfNeeded:
                    try await sshTerminalSession.resumeIfNeeded()
                }
                readinessTelemetry.reconnectSuccesses += 1
                readinessTelemetry.lastReconnectLatencyMs = Self.elapsedMilliseconds(since: reconnectStartedAt)
                readinessTelemetry.lastUpdatedAt = Date()
                reconnectAttemptMessage = nil
                persistResumeSnapshot()
                return
            } catch {
                if attempt == maxAttempts {
                    readinessTelemetry.reconnectFailures += 1
                    readinessTelemetry.lastUpdatedAt = Date()
                    reconnectAttemptMessage = nil
                    let prefix = mode == .resumeIfNeeded
                        ? "Terminal resume failed"
                        : "Terminal reconnect failed"
                    state = .failed("\(prefix) after \(maxAttempts) attempts: \(error.localizedDescription)")
                    return
                }
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 2_000_000_000)
            }
        }
    }

    func estimateGridSize(for size: CGSize) -> (cols: Int, rows: Int)? {
        guard size.width > 10, size.height > 10 else { return nil }

        let cellWidth = IOSTerminalLayoutMetrics.cellWidth
        let cellHeight = IOSTerminalLayoutMetrics.cellHeight

        let estimatedCols = min(max(Int(floor(size.width / cellWidth)), 20), 400)
        let estimatedRows = min(max(Int(floor(size.height / cellHeight)), 5), 200)

        if let lastAppliedViewportGrid,
           lastAppliedViewportGrid.cols == estimatedCols,
           lastAppliedViewportGrid.rows == estimatedRows {
            return nil
        }

        if sshTerminalSession.sessionID != nil {
            let colDelta = abs(sshTerminalSession.cols - estimatedCols)
            let rowDelta = abs(sshTerminalSession.rows - estimatedRows)
            if colDelta == 0, rowDelta == 0 {
                return nil
            }
            if colDelta < 2, rowDelta < 1 {
                return nil
            }
        }

        return (cols: estimatedCols, rows: estimatedRows)
    }

    var isTerminalActivelyConnected: Bool {
        switch sshTerminalSession.state {
        case .running, .reconnecting:
            return true
        case .idle, .connecting, .failed, .closed:
            return false
        }
    }

    enum ReconnectMode {
        case manualReconnect
        case resumeIfNeeded
    }
}
