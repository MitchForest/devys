import AppFeatures
import Foundation
import Split
import Workspace

@MainActor
struct WorkspaceViewState {
    var editorSessions: [TabID: EditorSession] = [:]
    var closeBypass: Set<TabID> = []
    var closeInFlight: Set<TabID> = []
}

@MainActor
extension ContentView {
    func allPaneIDs(in workspaceID: Workspace.ID? = nil) -> [PaneID] {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return [] }
        return store.workspaceShells[workspaceID]?.layout?.allPaneIDs ?? []
    }

    func targetPaneID(
        preferred preferredPaneID: PaneID? = nil,
        workspaceID: Workspace.ID? = nil
    ) -> PaneID? {
        if let preferredPaneID {
            return preferredPaneID
        }
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return nil }
        let shell = store.workspaceShells[workspaceID]
        return shell?.focusedPaneID
            ?? shell?.layout?.focusedFallbackPaneID
            ?? allPaneIDs(in: workspaceID).first
    }

    func insertionIndexForNewTab(
        in paneID: PaneID,
        workspaceID: Workspace.ID? = nil
    ) -> Int? {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID,
              let layout = store.workspaceShells[workspaceID]?.layout,
              let pane = layout.paneLayout(for: paneID) else {
            return nil
        }

        switch controller.configuration.newTabPosition {
        case .current:
            guard let selectedTabID = pane.selectedTabID,
                  let currentIndex = pane.tabIDs.firstIndex(of: selectedTabID) else {
                return nil
            }
            return currentIndex + 1

        case .end:
            return nil
        }
    }

    func renderWorkspaceLayout(
        for workspaceID: Workspace.ID? = nil,
        controller: DevysSplitController? = nil
    ) {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID,
              let layout = store.workspaceShells[workspaceID]?.layout else {
            return
        }
        ensureBrowserSessions(for: workspaceID)
        let splitController = controller ?? self.controller
        splitController.restoreTreeSnapshot(
            controllerSnapshot(from: layout, workspaceID: workspaceID),
            focusedPaneId: store.workspaceShells[workspaceID]?.focusedPaneID
        )
        syncTabMetadataFromSessions()
    }

    func ensureWorkspaceLayout(for workspaceID: Workspace.ID) {
        if store.workspaceShells[workspaceID]?.layout != nil {
            return
        }

        let layout = WindowFeature.WorkspaceLayout()
        store.send(.setWorkspaceLayout(workspaceID: workspaceID, layout: layout))
        store.send(
            .setWorkspaceFocusedPaneID(
                workspaceID: workspaceID,
                paneID: layout.focusedFallbackPaneID
            )
        )
    }

    func focusPane(
        _ paneID: PaneID,
        workspaceID: Workspace.ID? = nil
    ) {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return }
        store.send(.setWorkspaceFocusedPaneID(workspaceID: workspaceID, paneID: paneID))
        renderWorkspaceLayout(for: workspaceID)
    }

    @discardableResult
    func handleSplitGestureIntent(_ intent: SplitGestureIntent) -> Bool {
        guard let workspaceID = selectedWorkspaceID else { return false }
        let action = SplitGestureReducerAdapter().action(
            for: intent,
            workspaceID: workspaceID
        )
        store.send(action)
        renderWorkspaceLayout(for: workspaceID)
        return true
    }

    @discardableResult
    func splitPane(
        _ paneID: PaneID,
        orientation: Split.SplitOrientation,
        insertion: WindowFeature.SplitInsertionPosition = .after,
        workspaceID: Workspace.ID? = nil
    ) -> PaneID? {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return nil }
        let newPaneID = PaneID()
        store.send(
            .splitWorkspacePane(
                workspaceID: workspaceID,
                paneID: paneID,
                newPaneID: newPaneID,
                orientation: orientation,
                insertion: insertion
            )
        )
        renderWorkspaceLayout(for: workspaceID)
        return newPaneID
    }

    @discardableResult
    func splitTab(
        _ tabID: TabID,
        from sourcePaneID: PaneID,
        sourceIndex: Int,
        into targetPaneID: PaneID,
        orientation: Split.SplitOrientation,
        insertion: WindowFeature.SplitInsertionPosition,
        workspaceID: Workspace.ID? = nil
    ) -> PaneID? {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return nil }
        let newPaneID = PaneID()
        store.send(
            .splitWorkspacePaneWithTab(
                workspaceID: workspaceID,
                targetPaneID: targetPaneID,
                newPaneID: newPaneID,
                tabID: tabID,
                sourcePaneID: sourcePaneID,
                sourceIndex: sourceIndex,
                orientation: orientation,
                insertion: insertion
            )
        )
        renderWorkspaceLayout(for: workspaceID)
        return newPaneID
    }

    func closeTab(
        _ tabID: TabID,
        in paneID: PaneID,
        workspaceID: Workspace.ID? = nil
    ) {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return }
        store.send(.closeWorkspaceTab(workspaceID: workspaceID, paneID: paneID, tabID: tabID))
        renderWorkspaceLayout(for: workspaceID)
    }

    func persistedWorkspaceViewState(for workspaceID: Workspace.ID) -> WorkspaceViewState {
        workspaceViewStatesByID[workspaceID] ?? WorkspaceViewState()
    }

    func clearPreviewTabID(_ tabID: TabID, workspaceID: Workspace.ID? = nil) {
        guard let workspaceID = workspaceID ?? selectedWorkspaceID else { return }
        store.send(.clearWorkspacePreviewTabID(workspaceID: workspaceID, tabID: tabID))
    }

    func controllerSnapshot(
        from layout: WindowFeature.WorkspaceLayout,
        workspaceID: Workspace.ID
    ) -> ExternalTreeNode {
        controllerSnapshotNode(
            from: layout.root,
            workspaceID: workspaceID
        )
    }

    private func controllerSnapshotNode(
        from node: WindowFeature.WorkspaceLayoutNode,
        workspaceID: Workspace.ID
    ) -> ExternalTreeNode {
        switch node {
        case .pane(let pane):
            let tabs = pane.tabIDs.map { tabID in
                ExternalTab(
                    id: tabID.uuidString,
                    title: tabTitle(for: tabID, workspaceID: workspaceID)
                )
            }
            return .pane(
                ExternalPaneNode(
                    id: pane.id.uuidString,
                    frame: PixelRect(x: 0, y: 0, width: 0, height: 0),
                    tabs: tabs,
                    selectedTabId: pane.selectedTabID?.uuidString
                )
            )

        case .split(let split):
            return .split(
                ExternalSplitNode(
                    id: split.id.uuidString,
                    orientation: split.orientation == .horizontal ? "horizontal" : "vertical",
                    dividerPosition: split.dividerPosition,
                    first: controllerSnapshotNode(from: split.first, workspaceID: workspaceID),
                    second: controllerSnapshotNode(from: split.second, workspaceID: workspaceID)
                )
            )
        }
    }

    private func tabTitle(for tabID: TabID, workspaceID: Workspace.ID) -> String {
        if let presentation = tabPresentationById[tabID] {
            return presentation.title
        }
        if let content = store.workspaceShells[workspaceID]?.tabContents[tabID] {
            return tabMetadata(for: content).title
        }
        return "Tab"
    }
}
