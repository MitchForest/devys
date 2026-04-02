import Foundation
import ServerProtocol

extension IOSClientConnectionStore {
    func handleLaunchModeChanged() {
        if launchMode == .attachExisting, selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
        persistConnectionDraft()
    }

    func handleSelectedCommandProfileChanged() {
        if commandProfiles.contains(where: { $0.id == selectedCommandProfileID }) == false {
            selectedCommandProfileID = selectedCommandProfile.id
        }
        persistConnectionDraft()
    }

    func launchTerminal(cols: Int? = nil, rows: Int? = nil) {
        guard let baseURL = connectedBaseURL else {
            state = .failed("Connect to legacy mac-server first")
            return
        }
        guard canLaunchTerminal else {
            state = .failed(launchValidationMessage ?? "Terminal launch requirements are not met.")
            return
        }

        let request = prepareTerminalLaunchRequest(baseURL: baseURL, cols: cols, rows: rows)
        Task {
            await executeTerminalLaunch(request)
        }
    }

    func reconnectTerminal() {
        Task {
            await attemptTerminalReconnect(mode: .manualReconnect)
        }
    }

    func resumeTerminalIfPossible() {
        Task {
            await attemptTerminalReconnect(mode: .resumeIfNeeded)
        }
    }

    func disconnectTerminal() {
        shouldResumeOnActive = false
        pendingViewportResizeTask?.cancel()
        pendingViewportResizeTask = nil
        promptObservationTask?.cancel()
        promptObservationTask = nil
        sshTerminalSession.disconnect()
        terminalSession.disconnect()
        persistResumeSnapshot()
    }

    func stopActiveRun() {
        guard let baseURL = connectedBaseURL, let sessionID = terminalSession.sessionID else { return }

        Task {
            do {
                _ = try await client.stopSession(baseURL: baseURL, sessionID: sessionID)
                refreshSessions()
            } catch {
                state = .failed("Stop failed: \(error.localizedDescription)")
            }
        }
    }

    func resetReadinessTelemetry() {
        readinessTelemetry = ReadinessTelemetrySnapshot()
    }
}

private extension IOSClientConnectionStore {
    struct TerminalLaunchRequest {
        let baseURL: URL
        let workspacePath: String?
        let sessionID: String?
        let shouldRunSelectedProfile: Bool
        let selectedProfile: CommandProfile
        let requestedCols: Int
        let requestedRows: Int
        let startedAt: Date
    }

    func prepareTerminalLaunchRequest(baseURL: URL, cols: Int?, rows: Int?) -> TerminalLaunchRequest {
        let requestedCols = cols ?? preferredTerminalCols
        let requestedRows = rows ?? preferredTerminalRows
        preferredTerminalCols = requestedCols
        preferredTerminalRows = requestedRows

        readinessTelemetry.terminalLaunchAttempts += 1
        readinessTelemetry.lastUpdatedAt = Date()
        promptObservationTask?.cancel()
        promptObservationTask = nil

        return TerminalLaunchRequest(
            baseURL: baseURL,
            workspacePath: normalizedWorkspacePath,
            sessionID: launchMode == .attachExisting ? selectedSessionID : nil,
            shouldRunSelectedProfile: launchMode == .newSession,
            selectedProfile: selectedCommandProfile,
            requestedCols: requestedCols,
            requestedRows: requestedRows,
            startedAt: Date()
        )
    }

    func executeTerminalLaunch(_ request: TerminalLaunchRequest) async {
        do {
            try await terminalSession.connect(
                baseURL: request.baseURL,
                workspacePath: request.workspacePath,
                sessionID: request.sessionID,
                terminalID: terminalSession.terminalID,
                cols: request.requestedCols,
                rows: request.requestedRows
            )

            try await launchCommandProfileIfNeeded(request)
            handleTerminalLaunchSuccess(request)
        } catch {
            readinessTelemetry.terminalLaunchFailures += 1
            readinessTelemetry.lastUpdatedAt = Date()
            state = .failed("Terminal launch failed: \(error.localizedDescription)")
        }
    }

    func launchCommandProfileIfNeeded(_ request: TerminalLaunchRequest) async throws {
        guard request.shouldRunSelectedProfile else { return }
        guard let launchedSessionID = terminalSession.sessionID else { return }

        let command = request.selectedProfile.command?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let command, !command.isEmpty else { return }

        readinessTelemetry.profileLaunchAttempts += 1
        readinessTelemetry.lastProfileLaunchProfileID = request.selectedProfile.id

        do {
            _ = try await client.runSession(
                baseURL: request.baseURL,
                sessionID: launchedSessionID,
                command: command,
                arguments: request.selectedProfile.arguments,
                workingDirectory: request.workspacePath,
                environment: request.selectedProfile.environment
            )
            readinessTelemetry.profileLaunchSuccesses += 1
            readinessTelemetry.lastProfileLaunchError = nil
        } catch {
            readinessTelemetry.profileLaunchFailures += 1
            readinessTelemetry.lastProfileLaunchError = error.localizedDescription
            throw error
        }
    }

    func handleTerminalLaunchSuccess(_ request: TerminalLaunchRequest) {
        readinessTelemetry.terminalLaunchSuccesses += 1
        readinessTelemetry.lastUpdatedAt = Date()
        selectedSessionID = terminalSession.sessionID
        persistConnectionDraft()
        persistResumeSnapshot()
        beginPromptLatencyObservation(startedAt: request.startedAt)
        refreshSessions()
    }

    func beginPromptLatencyObservation(startedAt: Date) {
        promptObservationTask?.cancel()
        promptObservationTask = Task { [weak self] in
            guard let self else { return }
            let pollInterval: UInt64 = 120_000_000
            let timeout: UInt64 = 14_000_000_000
            let started = DispatchTime.now().uptimeNanoseconds

            while !Task.isCancelled {
                if outputContainsLikelyPrompt(terminalSession.outputPreview) {
                    readinessTelemetry.lastTimeToPromptMs = Self.elapsedMilliseconds(since: startedAt)
                    readinessTelemetry.lastUpdatedAt = Date()
                    return
                }

                let now = DispatchTime.now().uptimeNanoseconds
                if now >= started, now - started > timeout {
                    return
                }

                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
    }

    func outputContainsLikelyPrompt(_ output: String) -> Bool {
        guard !output.isEmpty else { return false }

        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reversed()

        for candidate in lines {
            let trimmed = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.count > 180 {
                return false
            }
            if trimmed.hasSuffix("$") || trimmed.hasSuffix("%") ||
                trimmed.hasSuffix("#") || trimmed.hasSuffix(">") {
                return true
            }
            if trimmed.localizedCaseInsensitiveContains("codex") ||
                trimmed.localizedCaseInsensitiveContains("claude") {
                return true
            }
            return false
        }

        return false
    }
}
