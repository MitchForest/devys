// ContentView+WorkspaceActions.swift
// Devys - Workspace row actions for the navigator.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import Git
import Workspace

@MainActor
extension ContentView {
    func setWorkspacePinned(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID,
        isPinned: Bool
    ) {
        guard navigatorWorktree(workspaceID, in: repositoryID) != nil else { return }
        workspaceCatalog.setWorkspacePinned(workspaceID, in: repositoryID, isPinned: isPinned)
    }

    func setWorkspaceArchived(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID,
        isArchived: Bool
    ) {
        guard let worktree = navigatorWorktree(workspaceID, in: repositoryID) else { return }

        workspaceCatalog.setWorkspaceArchived(worktree.id, in: repositoryID, isArchived: isArchived)
        syncCatalogStructure()
        if isArchived,
           workspaceCatalog.selectedRepositoryID == repositoryID,
           let replacementWorkspaceID = workspaceCatalog.selectedWorkspaceID,
           replacementWorkspaceID != worktree.id {
            Task { @MainActor in
                await selectWorkspace(replacementWorkspaceID, in: repositoryID)
            }
        }
    }

    func renameWorkspace(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) {
        guard let worktree = navigatorWorktree(workspaceID, in: repositoryID) else { return }

        let existingDisplayName = workspaceCatalog.displayName(for: worktree)
        let updatedDisplayName = promptForWorkspaceDisplayName(
            currentValue: existingDisplayName,
            branchName: worktree.name
        )
        guard let updatedDisplayName else { return }

        let normalizedDisplayName = updatedDisplayName == worktree.name ? nil : updatedDisplayName
        workspaceCatalog.setWorkspaceDisplayName(normalizedDisplayName, for: worktree.id, in: repositoryID)
    }

    func deleteWorkspace(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) async {
        guard let worktree = navigatorWorktree(workspaceID, in: repositoryID) else { return }

        guard !worktree.isPrimary else {
            showSimpleAlert(
                style: .warning,
                title: "Primary Workspace Cannot Be Deleted",
                message: "Delete the repository instead, or remove a non-primary workspace."
            )
            return
        }

        guard confirmWorkspaceDeletion(worktree) else { return }

        do {
            try await DefaultGitWorktreeService().removeWorktree(worktree, force: false)
            discardWorkspaceState(worktree.id)
            workspaceCatalog.removeWorkspaceState(worktree.id, in: repositoryID)
            await refreshRepositoryCatalog(repositoryID: repositoryID)
            if let selectedWorkspaceID = workspaceCatalog.selectedWorkspaceID,
               workspaceCatalog.selectedRepositoryID == repositoryID {
                await selectWorkspace(selectedWorkspaceID, in: repositoryID)
            }
        } catch {
            showSimpleAlert(
                style: .critical,
                title: "Delete Workspace Failed",
                message: error.localizedDescription
            )
        }
    }

    func revealWorkspaceInFinder(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) {
        guard let worktree = navigatorWorktree(workspaceID, in: repositoryID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
    }

    func openWorkspaceInExternalEditor(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) {
        guard let worktree = navigatorWorktree(workspaceID, in: repositoryID) else { return }

        if let bundleIdentifier = appSettings.shell.defaultExternalEditorBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                showSimpleAlert(
                    style: .warning,
                    title: "External Editor Not Found",
                    message: "No installed app matches \(bundleIdentifier)."
                )
                return
            }

            NSWorkspace.shared.open(
                [worktree.workingDirectory],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error {
                    Task { @MainActor in
                        showSimpleAlert(
                            style: .critical,
                            title: "Open in External Editor Failed",
                            message: error.localizedDescription
                        )
                    }
                }
            }
            return
        }

        NSWorkspace.shared.open(worktree.workingDirectory)
    }

    private func promptForWorkspaceDisplayName(
        currentValue: String,
        branchName: String
    ) -> String?? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rename Workspace"
        alert.informativeText = "Set a display name for \(branchName). Leave it empty to use the branch name."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = currentValue
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let displayName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayName.isEmpty ? .some(nil) : .some(displayName)
    }

    private func confirmWorkspaceDeletion(_ worktree: Worktree) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Workspace?"
        alert.informativeText = """
        This removes the worktree at:

        \(worktree.workingDirectory.path)
        """
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showSimpleAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func navigatorWorktree(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) -> Worktree? {
        navigatorWorktreesByRepository[repositoryID]?.first { $0.id == workspaceID }
    }
}
