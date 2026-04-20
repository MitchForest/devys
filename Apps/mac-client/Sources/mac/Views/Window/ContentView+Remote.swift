import AppFeatures
import Foundation
import GhosttyTerminal
import RemoteCore
import Split
import UI
import Workspace

@MainActor
extension ContentView {
    func saveRemoteRepository(_ authority: RemoteRepositoryAuthority) {
        store.send(.upsertRemoteRepository(authority))
        store.send(.setRemoteRepositoryPresentation(nil))
        refreshRemoteRepository(authority.id)
    }

    func presentRemoteWorktreeCreation(
        for repositoryID: RemoteRepositoryAuthority.ID
    ) {
        store.send(
            .setRemoteWorktreeCreationPresentation(
                RemoteWorktreeCreationPresentation(
                    draft: RemoteWorktreeDraft(repositoryID: repositoryID)
                )
            )
        )
    }

    func selectRemoteWorktree(
        _ workspaceID: RemoteWorktree.ID,
        in repositoryID: RemoteRepositoryAuthority.ID
    ) {
        store.send(
            .requestRemoteWorktreeSelection(
                repositoryID: repositoryID,
                workspaceID: workspaceID
            )
        )
    }

    func refreshRemoteRepository(
        _ repositoryID: RemoteRepositoryAuthority.ID
    ) {
        store.send(.refreshRemoteRepository(repositoryID))
    }

    func fetchRemoteRepository(
        _ repositoryID: RemoteRepositoryAuthority.ID
    ) {
        store.send(.fetchRemoteRepository(repositoryID))
    }

    func pullRemoteWorktree(
        _ workspaceID: RemoteWorktree.ID,
        in repositoryID: RemoteRepositoryAuthority.ID
    ) {
        store.send(.pullRemoteWorktree(repositoryID: repositoryID, workspaceID: workspaceID))
    }

    func pushRemoteWorktree(
        _ workspaceID: RemoteWorktree.ID,
        in repositoryID: RemoteRepositoryAuthority.ID
    ) {
        store.send(.pushRemoteWorktree(repositoryID: repositoryID, workspaceID: workspaceID))
    }

    func createRemoteWorktree(
        _ draft: RemoteWorktreeDraft
    ) {
        store.send(.createRemoteWorktree(draft))
    }

    func executeRemoteTerminalLaunch(
        _ request: WindowFeature.RemoteTerminalLaunchRequest
    ) async {
        if let preferredPaneID = request.preferredPaneID {
            store.send(.setWorkspaceFocusedPaneID(workspaceID: request.workspaceID, paneID: preferredPaneID))
            renderWorkspaceLayout(for: request.workspaceID)
        }

        do {
            let session = createPendingHostedTerminalSession(
                in: request.workspaceID,
                requestedCommand: request.attachCommand,
                tabIcon: "terminal",
                traceSource: "remote-terminal",
                launchProfile: .compatibilityShell,
                openMode: "permanent"
            )

            let content = WorkspaceTabContent.terminal(workspaceID: request.workspaceID, id: session.id)
            if let preferredPaneID = request.preferredPaneID {
                guard createTab(in: preferredPaneID, content: content) != nil else {
                    shutdownWorkspaceTerminalSession(
                        id: session.id,
                        in: request.workspaceID,
                        terminateHostedSession: false
                    )
                    endTerminalOpenTrace(
                        sessionID: session.id,
                        outcome: "failed",
                        context: ["error": "Could not open a terminal tab."]
                    )
                    throw NSError(domain: "DevysRemoteTerminal", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Could not open a terminal tab."
                    ])
                }
            } else {
                openInPermanentTab(content: content)
            }
            try await startPendingHostedTerminalSession(
                session,
                in: request.workspaceID,
                requestedCommand: request.attachCommand,
                launchProfile: .compatibilityShell,
                traceSource: "remote-terminal"
            )
            persistTerminalRelaunchSnapshotIfNeeded()
        } catch {
            showLauncherUnavailableAlert(
                title: "Remote Shell Unavailable",
                message: error.localizedDescription
            )
        }
    }

    func resetVisibleWorkspaceRuntime() {
        clearVisibleWorkspaceTabContents()
        tabPresentationById.removeAll()
        editorSessions.removeAll()
        closeBypass.removeAll()
        closeInFlight.removeAll()
        controller = ContentView.makeSplitController()
        configureSplitDelegate()
        store.send(.setActiveSidebar(.files))
        runtimeRegistry.deactivateActiveWorkspace()
    }
}
