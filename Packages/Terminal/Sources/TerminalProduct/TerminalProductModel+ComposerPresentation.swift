import Foundation
import TerminalComposer
import TerminalHost

extension TerminalProductModel {
    /// Resolves an observed foreground process against the registry. The composer is
    /// always visible; foreground detection only updates serialization and chrome state.
    func applyForegroundProcess(_ process: TerminalForegroundProcess?) {
        currentForegroundProcess = process
        let match = agentRegistry.match(
            executableName: process?.executableName,
            title: currentTerminalTitle
        )
        guard agentContext.match != match else {
            refreshAgentActivity()
            refreshWindowTitle()
            refreshCloseRisk()
            return
        }

        lastAgentOutputAt = nil
        agentContext = TerminalAgentContext(match: match, activity: .waiting)
        refreshWindowTitle()
        refreshCloseRisk()
    }

    func startForegroundProbe() {
        foregroundProbeTask?.cancel()
        foregroundProbeTask = Task { [weak self] in
            await self?.runForegroundProbeLoop()
        }
    }

    func stopForegroundProbe() {
        foregroundProbeTask?.cancel()
        foregroundProbeTask = nil
    }

    private func runForegroundProbeLoop() async {
        while !Task.isCancelled {
            guard let handle = currentSessionHandle, !hasTerminalExited else { return }
            let process = await host.foregroundProcess(handle)
            applyForegroundProcess(process)
            if let workingDirectory = await host.currentWorkingDirectory(handle) {
                updateTerminalTitle(
                    title: currentTerminalTitle ?? "",
                    workingDirectory: workingDirectory.path
                )
            }
            refreshAgentActivity()
            do {
                try await Task.sleep(for: foregroundProbeInterval)
            } catch {
                return
            }
        }
    }

    func noteAgentOutput(at date: Date = Date()) {
        guard agentContext.match != nil else { return }
        lastAgentOutputAt = date
        agentContext.activity = .working
    }

    func refreshAgentActivity(now: Date = Date()) {
        guard agentContext.match != nil else {
            agentContext.activity = .waiting
            return
        }
        guard let lastAgentOutputAt else {
            agentContext.activity = .waiting
            return
        }
        agentContext.activity = now.timeIntervalSince(lastAgentOutputAt) < agentWorkingQuietInterval
            ? .working
            : .waiting
    }

    func refreshCloseRisk() {
        guard !hasTerminalExited,
              let process = currentForegroundProcess,
              Self.normalizedForegroundProcessName(process.executableName) != nil else {
            closeRisk = nil
            return
        }

        if let match = agentContext.match {
            closeRisk = .knownAgent(displayName: match.displayName, process: process)
        } else {
            closeRisk = .foregroundProcess(process)
        }
    }
}
