// WorkspaceBackgroundProcessRegistry.swift
// Devys - Workspace-owned background process runtime.

import Foundation
import Observation
import Workspace

@MainActor
final class ManagedBackgroundProcess: Identifiable {
    let id: UUID
    let displayName: String
    let process: Process

    init(
        id: UUID = UUID(),
        displayName: String,
        process: Process
    ) {
        self.id = id
        self.displayName = displayName
        self.process = process
    }
}

@MainActor
@Observable
final class WorkspaceBackgroundProcessRegistry {
    private(set) var processesByWorkspace: [Workspace.ID: [UUID: ManagedBackgroundProcess]] = [:]

    func launch(
        in workspaceID: Workspace.ID,
        stepID _: StartupProfileStep.ID,
        displayName: String,
        workingDirectory: URL,
        command: String,
        environment: [String: String] = [:],
        onTermination: (@MainActor (UUID, Workspace.ID) -> Void)? = nil
    ) throws -> ManagedBackgroundProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory

        var mergedEnvironment = colorCapableEnvironment(ProcessInfo.processInfo.environment)
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

        let managedProcess = ManagedBackgroundProcess(
            displayName: displayName,
            process: process
        )
        let managedProcessID = managedProcess.id

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.removeProcess(id: managedProcessID, in: workspaceID)
                onTermination?(managedProcessID, workspaceID)
            }
        }

        try process.run()

        var workspaceProcesses = processesByWorkspace[workspaceID] ?? [:]
        workspaceProcesses[managedProcess.id] = managedProcess
        processesByWorkspace[workspaceID] = workspaceProcesses
        return managedProcess
    }

    func shutdown(id: UUID, in workspaceID: Workspace.ID) {
        guard let managedProcess = processesByWorkspace[workspaceID]?[id] else { return }
        managedProcess.process.terminate()
        removeProcess(id: id, in: workspaceID)
    }

    func shutdownAll(in workspaceID: Workspace.ID) {
        guard let workspaceProcesses = processesByWorkspace[workspaceID] else { return }
        for managedProcess in workspaceProcesses.values {
            managedProcess.process.terminate()
        }
        processesByWorkspace.removeValue(forKey: workspaceID)
    }

    private func removeProcess(id: UUID, in workspaceID: Workspace.ID) {
        guard var workspaceProcesses = processesByWorkspace[workspaceID] else { return }
        workspaceProcesses.removeValue(forKey: id)
        if workspaceProcesses.isEmpty {
            processesByWorkspace.removeValue(forKey: workspaceID)
        } else {
            processesByWorkspace[workspaceID] = workspaceProcesses
        }
    }
}
