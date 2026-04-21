import AppFeatures
import Split
import Workspace

@MainActor
extension ContentView {
    struct ClosedWorkspaceTab {
        let id: TabID
        let content: WorkspaceTabContent
        let wasPreview: Bool
    }

    func closeWorkspacePaneAndCleanup(
        _ paneID: PaneID,
        workspaceID: Workspace.ID
    ) {
        let closedTabs = closedTabs(in: paneID, workspaceID: workspaceID)
        store.send(.closeWorkspacePane(workspaceID: workspaceID, paneID: paneID))
        prepareClosedTabsForRemoval(closedTabs)
        renderWorkspaceLayout(for: workspaceID)
        cleanupClosedTabs(closedTabs)
    }

    func prepareClosedTabsForRemoval(_ closedTabs: [ClosedWorkspaceTab]) {
        for closedTab in closedTabs {
            tabPresentationById.removeValue(forKey: closedTab.id)
            removeTabContent(for: closedTab.id, content: closedTab.content)

            if closedTab.wasPreview {
                clearPreviewTabID(closedTab.id, workspaceID: closedTab.content.workspaceID)
            }
        }
    }

    func cleanupClosedTabs(_ closedTabs: [ClosedWorkspaceTab]) {
        for closedTab in closedTabs {
            cleanupSession(for: closedTab.content, tabId: closedTab.id)
        }
    }

    private func closedTabs(
        in paneID: PaneID,
        workspaceID: Workspace.ID
    ) -> [ClosedWorkspaceTab] {
        guard let shell = store.workspaceShells[workspaceID],
              let pane = shell.layout?.paneLayout(for: paneID) else {
            return []
        }

        return pane.tabIDs.compactMap { tabID in
            guard let content = shell.tabContents[tabID] else { return nil }
            return closedWorkspaceTab(
                id: tabID,
                content: content,
                paneID: paneID,
                workspaceID: workspaceID
            )
        }
    }

    func closedWorkspaceTab(
        id: TabID,
        content: WorkspaceTabContent,
        paneID: PaneID,
        workspaceID: Workspace.ID
    ) -> ClosedWorkspaceTab {
        let wasPreview = store.workspaceShells[workspaceID]?.layout?.paneLayout(for: paneID)?.previewTabID == id
        return ClosedWorkspaceTab(id: id, content: content, wasPreview: wasPreview)
    }
}
