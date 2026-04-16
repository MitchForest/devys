// WorkspacePortManagedProcessCatalog.swift
// Devys - Merge direct ownership signals for workspace port attribution.

import AppFeatures
import Foundation
import Workspace

struct WorkspacePortManagedProcessCatalog {
    static func makeManagedProcesses(
        backgroundProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]],
        hostedSessionsByID: [UUID: HostedTerminalSessionRecord]
    ) -> [Workspace.ID: [ManagedWorkspaceProcess]] {
        var managedProcessesByWorkspace: [Workspace.ID: [Int32: ManagedWorkspaceProcess]] = [:]

        for (workspaceID, processes) in backgroundProcessesByWorkspace {
            for process in processes {
                insert(
                    process,
                    into: workspaceID,
                    managedProcessesByWorkspace: &managedProcessesByWorkspace
                )
            }
        }

        for hostedSession in hostedSessionsByID.values {
            guard let processID = hostedSession.processID else { continue }
            insert(
                ManagedWorkspaceProcess(
                    processID: processID,
                    displayName: hostedSessionDisplayName(for: hostedSession)
                ),
                into: hostedSession.workspaceID,
                managedProcessesByWorkspace: &managedProcessesByWorkspace
            )
        }

        return managedProcessesByWorkspace.mapValues { processesByID in
            processesByID.values.sorted { lhs, rhs in
                lhs.processID < rhs.processID
            }
        }
    }

    private static func insert(
        _ process: ManagedWorkspaceProcess,
        into workspaceID: Workspace.ID,
        managedProcessesByWorkspace: inout [Workspace.ID: [Int32: ManagedWorkspaceProcess]]
    ) {
        var workspaceProcesses = managedProcessesByWorkspace[workspaceID] ?? [:]
        workspaceProcesses[process.processID] = process
        managedProcessesByWorkspace[workspaceID] = workspaceProcesses
    }

    private static func hostedSessionDisplayName(for hostedSession: HostedTerminalSessionRecord) -> String {
        hostedSession.launchCommand?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Terminal"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
