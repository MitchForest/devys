import Foundation

extension HostedLocalTerminalController {
    func flushPendingOutputBuffer() async {
        guard !pendingOutput.isEmpty else { return }
        let bufferedOutput = pendingOutput
        pendingOutput.removeAll(keepingCapacity: true)
        guard let runtime else { return }
        let result = await runtime.write(bufferedOutput)
        for outboundWrite in result.outboundWrites {
            await MainActor.run {
                self.sendOrQueueFrame(type: .input, payload: outboundWrite)
            }
        }

        apply(update: result.surfaceUpdate, advancesStartup: true)
        session.tabTitle = result.title
        session.currentDirectory = result.workingDirectory.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        session.bellCount += result.bellCountDelta
        session.lastErrorDescription = nil
        session.isRunning = true
    }

    func scheduleOutputFlushIfNeeded() {
        guard outputFlushTask == nil else { return }

        // Batch redraw-heavy PTY bursts so apps like Codex land as one VT update
        // instead of exposing intermediate cursor positions between chunks.
        outputFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.outputBurstWindow)
            guard Task.isCancelled == false else { return }
            self.outputFlushTask = nil
            await self.flushPendingOutputBuffer()
        }
    }
}
