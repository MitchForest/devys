import Foundation
import AppFeatures
import Testing
import Workspace
@testable import mac_client

struct StubWorkspacePortSnapshotProvider: WorkspacePortSnapshotProvider {
    let snapshots: [[Workspace.ID: [WorkspacePort]]]
    private let index = LockedCounter()

    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]] {
        _ = context
        let currentIndex = index.next()
        if currentIndex < snapshots.count {
            return snapshots[currentIndex]
        }
        return snapshots.last ?? [:]
    }
}

actor CountingWorkspacePortSnapshotProvider: WorkspacePortSnapshotProvider {
    let snapshot: [Workspace.ID: [WorkspacePort]]
    private var refreshCountStorage = 0

    init(snapshot: [Workspace.ID: [WorkspacePort]]) {
        self.snapshot = snapshot
    }

    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]] {
        _ = context
        refreshCountStorage += 1
        return snapshot
    }

    func refreshCount() -> Int {
        refreshCountStorage
    }
}

actor ContextRecordingWorkspacePortSnapshotProvider: WorkspacePortSnapshotProvider {
    private var requestedWorkspaceIDsStorage: [[Workspace.ID]] = []

    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]] {
        let workspaceIDs = context.worktreesByID.keys.sorted()
        requestedWorkspaceIDsStorage.append(workspaceIDs)
        return Dictionary(uniqueKeysWithValues: workspaceIDs.map { workspaceID in
            (
                workspaceID,
                [
                    WorkspacePort(
                        workspaceID: workspaceID,
                        port: 3000,
                        processIDs: [111],
                        processNames: ["node"],
                        ownership: .owned
                    )
                ]
            )
        })
    }

    func requestedWorkspaceIDs() -> [[Workspace.ID]] {
        requestedWorkspaceIDsStorage
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}

func commandRunner(
    listeningOutput: String,
    processOutput: String,
    workingDirectoryOutputs: [String: String]
) -> DefaultWorkspacePortSnapshotProvider.CommandRunner {
    { executable, arguments in
        if executable == "/usr/sbin/lsof",
           arguments == ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"] {
            return listeningOutput
        }

        if executable == "/bin/ps",
           arguments == ["-axo", "pid=,ppid="] {
            return processOutput
        }

        if executable == "/usr/sbin/lsof",
           arguments.count == 7,
           arguments[0] == "-a",
           arguments[1] == "-d",
           arguments[2] == "cwd",
           arguments[3] == "-p",
           arguments[5] == "-F",
           arguments[6] == "pn" {
            return workingDirectoryOutputs[arguments[4]] ?? ""
        }

        Issue.record("Unexpected command: \(executable) \(arguments.joined(separator: " "))")
        return ""
    }
}
