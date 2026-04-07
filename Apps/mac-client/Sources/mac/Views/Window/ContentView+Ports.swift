// ContentView+Ports.swift
// Devys - Workspace port actions and URL resolution.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import Darwin
import Workspace

@MainActor
extension ContentView {
    func openPort(_ port: WorkspacePort, label: RepositoryPortLabel?) {
        guard let url = resolvedURL(for: port, label: label) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyPortURL(_ port: WorkspacePort, label: RepositoryPortLabel?) {
        guard let url = resolvedURL(for: port, label: label) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func stopPortProcess(_ port: WorkspacePort, processID: Int32) {
        if let managedProcess = managedBackgroundProcess(for: processID, workspaceID: port.workspaceID) {
            workspaceBackgroundProcessRegistry.shutdown(id: managedProcess.id, in: port.workspaceID)
            workspaceRunStore.removeBackgroundProcess(managedProcess.id)
            syncCatalogPortState()
        } else {
            Darwin.kill(processID, SIGTERM)
            runtimeRegistry.portCoordinator.refresh(workspaceIDs: [port.workspaceID])
        }
    }

    private func managedBackgroundProcess(
        for processID: Int32,
        workspaceID: Workspace.ID
    ) -> ManagedBackgroundProcess? {
        workspaceBackgroundProcessRegistry.processesByWorkspace[workspaceID]?.values.first {
            $0.process.processIdentifier == processID
        }
    }

    private func resolvedURL(for port: WorkspacePort, label: RepositoryPortLabel?) -> URL? {
        let scheme = label?.scheme.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "http"
        let normalizedPath = normalizedPortPath(label?.path ?? "")
        return URL(string: "\(scheme)://localhost:\(port.port)\(normalizedPath)")
    }

    private func normalizedPortPath(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
