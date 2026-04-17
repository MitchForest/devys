import AppFeatures
import Foundation
import GhosttyTerminal
import Observation
import Workspace

@MainActor
final class WorkflowExecutionController {
    private struct TrackedRun: Sendable {
        var workspaceID: Workspace.ID
        var terminalID: UUID
        var didEmitUpdate: Bool
        var didObserveRunning: Bool
        var expectsRestore: Bool
        var isHostedSession: Bool
    }

    private let workspaceOperationalController: WorkspaceOperationalController
    private let persistentTerminalHostController: PersistentTerminalHostController?
    private let restoreTerminalSessionsEnabled: @MainActor @Sendable () -> Bool
    private let fileManager: FileManager
    private var trackedRunsByID: [UUID: TrackedRun] = [:]
    private var continuations: [UUID: AsyncStream<WorkflowExecutionUpdate>.Continuation] = [:]
    private var isObservingTerminalState = false

    init(
        workspaceOperationalController: WorkspaceOperationalController,
        persistentTerminalHostController: PersistentTerminalHostController? = nil,
        restoreTerminalSessionsEnabled: @escaping @MainActor @Sendable () -> Bool = { false },
        fileManager: FileManager = .default
    ) {
        self.workspaceOperationalController = workspaceOperationalController
        self.persistentTerminalHostController = persistentTerminalHostController
        self.restoreTerminalSessionsEnabled = restoreTerminalSessionsEnabled
        self.fileManager = fileManager
    }

    func updates() -> AsyncStream<WorkflowExecutionUpdate> {
        ensureObservationStarted()

        let streamID = UUID()
        return AsyncStream { continuation in
            continuations[streamID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: streamID)
                }
            }
        }
    }

    func registerRuns(_ runs: [WorkflowRun]) async {
        let hostedSessionsByID = await hostedSessionsByID()
        var nextTrackedRuns: [UUID: TrackedRun] = [:]

        for run in runs {
            guard let terminalID = run.currentTerminalID else { continue }

            var session = workspaceOperationalController.terminalRegistry.session(
                id: terminalID,
                in: run.workspaceID
            )
            var isHostedSession = false
            var expectsRestore = false

            if session == nil,
               let hostedSession = hostedSessionsByID[terminalID],
               let restoredSession = await restoreHostedTerminalSession(
                   hostedSession,
                   workspaceID: run.workspaceID
               ) {
                session = restoredSession
                isHostedSession = true
            } else if hostedSessionsByID[terminalID] != nil {
                isHostedSession = true
            } else if restoreTerminalSessionsEnabled() {
                expectsRestore = true
            }

            nextTrackedRuns[run.id] = TrackedRun(
                workspaceID: run.workspaceID,
                terminalID: terminalID,
                didEmitUpdate: false,
                didObserveRunning: session?.isRunning == true,
                expectsRestore: expectsRestore,
                isHostedSession: isHostedSession
            )
        }

        trackedRunsByID = nextTrackedRuns
        ensureObservationStarted()
        emitTerminalUpdatesIfNeeded()
    }

    func startNode(
        _ request: WorkflowNodeLaunchRequest
    ) async throws -> WorkflowNodeLaunchResult {
        let promptArtifactURL = try writePromptArtifact(for: request)
        let command = try makeLaunchCommand(
            for: request.worker,
            promptArtifactURL: promptArtifactURL
        )

        let (session, isHostedSession) = try await launchWorkflowTerminalSession(
            request: request,
            command: command
        )

        trackedRunsByID[request.runID] = TrackedRun(
            workspaceID: request.workspaceID,
            terminalID: session.id,
            didEmitUpdate: false,
            didObserveRunning: session.isRunning,
            expectsRestore: false,
            isHostedSession: isHostedSession
        )
        ensureObservationStarted()

        return WorkflowNodeLaunchResult(
            terminalID: session.id,
            launchedCommand: command,
            promptArtifactPath: promptArtifactURL.path
        )
    }

    func stopRun(_ runID: UUID) {
        guard let trackedRun = trackedRunsByID[runID] else { return }
        if trackedRun.isHostedSession,
           let persistentTerminalHostController {
            Task {
                try? await persistentTerminalHostController.terminateSession(id: trackedRun.terminalID)
            }
            workspaceOperationalController.removeHostedSession(trackedRun.terminalID)
        }
        workspaceOperationalController.shutdownTerminalSession(
            id: trackedRun.terminalID,
            in: trackedRun.workspaceID
        )
    }
}

@MainActor
private extension WorkflowExecutionController {
    func ensureObservationStarted() {
        guard !isObservingTerminalState else { return }
        isObservingTerminalState = true
        observeTerminalState()
    }

    func observeTerminalState() {
        withObservationTracking {
            for trackedRun in trackedRunsByID.values.sorted(by: { lhs, rhs in
                if lhs.workspaceID != rhs.workspaceID {
                    return lhs.workspaceID < rhs.workspaceID
                }
                return lhs.terminalID.uuidString < rhs.terminalID.uuidString
            }) {
                let session = workspaceOperationalController.terminalRegistry.session(
                    id: trackedRun.terminalID,
                    in: trackedRun.workspaceID
                )
                _ = session?.isRunning
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.emitTerminalUpdatesIfNeeded()
                self?.observeTerminalState()
            }
        }
    }

    func emitTerminalUpdatesIfNeeded() {
        for (runID, trackedRun) in trackedRunsByID {
            let session = workspaceOperationalController.terminalRegistry.session(
                id: trackedRun.terminalID,
                in: trackedRun.workspaceID
            )

            if session?.isRunning == true {
                trackedRunsByID[runID]?.didObserveRunning = true
                trackedRunsByID[runID]?.expectsRestore = false
                continue
            }

            let hasExited = session == nil || session?.isRunning == false
            guard hasExited, !trackedRun.didEmitUpdate else { continue }

            trackedRunsByID[runID]?.didEmitUpdate = true
            let update: WorkflowExecutionUpdate
            if trackedRun.expectsRestore && !trackedRun.didObserveRunning {
                update = .terminalRestoreMissing(
                    runID: runID,
                    terminalID: trackedRun.terminalID
                )
            } else {
                update = .terminalExited(
                    runID: runID,
                    terminalID: trackedRun.terminalID
                )
            }

            if trackedRun.isHostedSession {
                workspaceOperationalController.removeHostedSession(trackedRun.terminalID)
            }
            for continuation in continuations.values {
                continuation.yield(update)
            }
        }
    }

    func hostedSessionsByID() async -> [UUID: HostedTerminalSessionRecord] {
        guard restoreTerminalSessionsEnabled(),
              let persistentTerminalHostController,
              let sessions = try? await persistentTerminalHostController.listSessions() else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    func launchWorkflowTerminalSession(
        request: WorkflowNodeLaunchRequest,
        command: String
    ) async throws -> (session: GhosttyTerminalSession, isHostedSession: Bool) {
        guard restoreTerminalSessionsEnabled(),
              let persistentTerminalHostController else {
            return (
                workspaceOperationalController.createTerminalSession(
                    in: request.workspaceID,
                    workingDirectory: request.workingDirectoryURL,
                    requestedCommand: command
                ),
                false
            )
        }

        let record = try await persistentTerminalHostController.createSession(
            workspaceID: request.workspaceID,
            workingDirectory: request.workingDirectoryURL,
            launchCommand: command
        )
        let attachCommand = await persistentTerminalHostController.attachCommand(for: record.id)
        workspaceOperationalController.upsertHostedSession(record)
        let session = workspaceOperationalController.createTerminalSession(
            in: request.workspaceID,
            workingDirectory: record.workingDirectory ?? request.workingDirectoryURL,
            attachCommand: attachCommand,
            terminateHostedSessionOnClose: true,
            id: record.id
        )
        return (session, true)
    }

    func restoreHostedTerminalSession(
        _ record: HostedTerminalSessionRecord,
        workspaceID: Workspace.ID
    ) async -> GhosttyTerminalSession? {
        guard restoreTerminalSessionsEnabled(),
              let persistentTerminalHostController else {
            return nil
        }

        let attachCommand = await persistentTerminalHostController.attachCommand(for: record.id)
        workspaceOperationalController.upsertHostedSession(record)
        return workspaceOperationalController.createTerminalSession(
            in: workspaceID,
            workingDirectory: record.workingDirectory,
            attachCommand: attachCommand,
            terminateHostedSessionOnClose: true,
            id: record.id
        )
    }

    func writePromptArtifact(
        for request: WorkflowNodeLaunchRequest
    ) throws -> URL {
        let promptsDirectoryURL = WorkflowStorageLocations.promptsDirectory(
            for: request.workingDirectoryURL,
            runID: request.runID,
            fileManager: fileManager
        )

        try fileManager.createDirectory(
            at: promptsDirectoryURL,
            withIntermediateDirectories: true
        )

        let fileName = "\(workflowPromptTimestamp())-\(request.node.id).md"
        let promptURL = promptsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
        try request.prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        return promptURL
    }

    func makeLaunchCommand(
        for worker: WorkflowWorker,
        promptArtifactURL: URL
    ) throws -> String {
        let promptExpression = "\"$(cat \(workflowShellQuoted(promptArtifactURL.path)))\""
        let executable = worker.launcher.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else {
            throw NSError(
                domain: "WorkflowExecutionController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Workflow launcher executable is empty."]
            )
        }

        switch (worker.kind, worker.executionMode) {
        case (.claude, .interactive):
            return ([executable]
                + claudeArguments(for: worker.launcher)
                + [promptExpression])
                .joined(separator: " ")

        case (.claude, .headless):
            return ([executable]
                + claudeArguments(for: worker.launcher)
                + ["-p", promptExpression])
                .joined(separator: " ")

        case (.codex, .interactive):
            return ([executable]
                + codexArguments(for: worker.launcher)
                + [promptExpression])
                .joined(separator: " ")

        case (.codex, .headless):
            return ([executable, "exec"]
                + codexArguments(for: worker.launcher)
                + [promptExpression])
                .joined(separator: " ")
        }
    }

    func claudeArguments(
        for launcher: LauncherTemplate
    ) -> [String] {
        var arguments: [String] = []
        if let model = workflowExecutionNormalizedOptionalString(launcher.model) {
            arguments.append(contentsOf: ["--model", workflowShellQuoted(model)])
        }
        if let reasoningLevel = workflowExecutionNormalizedOptionalString(launcher.reasoningLevel) {
            arguments.append(contentsOf: ["--effort", workflowShellQuoted(reasoningLevel)])
        }
        if launcher.dangerousPermissions {
            arguments.append("--dangerously-skip-permissions")
        }
        arguments.append(contentsOf: launcher.extraArguments.map(workflowShellQuoted))
        return arguments
    }

    func codexArguments(
        for launcher: LauncherTemplate
    ) -> [String] {
        var arguments: [String] = []
        if let model = workflowExecutionNormalizedOptionalString(launcher.model) {
            arguments.append(contentsOf: ["-m", workflowShellQuoted(model)])
        }
        if let reasoningLevel = workflowExecutionNormalizedOptionalString(launcher.reasoningLevel) {
            arguments.append(
                contentsOf: [
                    "-c",
                    workflowShellQuoted("model_reasoning_effort=\"\(reasoningLevel)\"")
                ]
            )
        }
        if launcher.dangerousPermissions {
            arguments.append("--dangerously-bypass-approvals-and-sandbox")
        }
        arguments.append(contentsOf: launcher.extraArguments.map(workflowShellQuoted))
        return arguments
    }
}

private func workflowPromptTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
}

private func workflowShellQuoted(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    if value.unicodeScalars.allSatisfy({ scalar in
        CharacterSet.alphanumerics.contains(scalar) || "/-._:=".unicodeScalars.contains(scalar)
    }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}

private func workflowExecutionNormalizedOptionalString(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
