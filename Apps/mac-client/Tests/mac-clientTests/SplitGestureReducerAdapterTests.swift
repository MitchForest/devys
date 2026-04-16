import AppFeatures
import ComposableArchitecture
import Foundation
import Split
import Testing
import Workspace
@testable import mac_client

@Suite("Split Gesture Reducer Adapter Tests")
struct SplitGestureReducerAdapterTests {
    @Test("Adapter maps split pane intents to explicit reducer actions")
    @MainActor
    func mapsSplitPaneIntent() {
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let paneID = PaneID()
        let newPaneID = PaneID()
        let adapter = SplitGestureReducerAdapter { newPaneID }

        let action = adapter.action(
            for: .splitPane(
                paneID: paneID,
                orientation: .horizontal,
                insertion: .before
            ),
            workspaceID: workspaceID
        )

        #expect(
            action == .splitWorkspacePane(
                workspaceID: workspaceID,
                paneID: paneID,
                newPaneID: newPaneID,
                orientation: .horizontal,
                insertion: .before
            )
        )
    }

    @Test("Adapter-driven split gestures update reducer-owned layout directly")
    @MainActor
    func splitGestureIntentReducesWithoutControllerSnapshot() async {
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let sourcePaneID = PaneID()
        let movedTabID = TabID()
        let newPaneID = PaneID()
        let adapter = SplitGestureReducerAdapter { newPaneID }
        let store = TestStore(
            initialState: initialState(
                workspaceID: workspaceID,
                sourcePaneID: sourcePaneID,
                movedTabID: movedTabID
            )
        ) {
            WindowFeature()
        }
        store.exhaustivity = .off
        await store.send(.selectWorkspace(workspaceID)) {
            $0.selectedWorkspaceID = workspaceID
        }

        let action = splitTabAction(
            adapter: adapter,
            workspaceID: workspaceID,
            sourcePaneID: sourcePaneID,
            movedTabID: movedTabID
        )

        await store.send(action) {
            $0.selectedTabID = movedTabID
            $0.workspaceShells[workspaceID]?.focusedPaneID = newPaneID
        }

        assertExpectedSplitLayout(
            store.state.workspaceShells[workspaceID]?.layout?.root,
            sourcePaneID: sourcePaneID,
            movedTabID: movedTabID,
            newPaneID: newPaneID
        )
    }
}

@MainActor
private extension SplitGestureReducerAdapterTests {
    func initialState(
        workspaceID: Workspace.ID,
        sourcePaneID: PaneID,
        movedTabID: TabID
    ) -> WindowFeature.State {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        return WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: sourcePaneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .pane(
                            WindowFeature.WorkspacePaneLayout(
                                id: sourcePaneID,
                                tabIDs: [movedTabID],
                                selectedTabID: movedTabID
                            )
                        )
                    )
                )
            ],
            selectedTabID: movedTabID
        )
    }

    func splitTabAction(
        adapter: SplitGestureReducerAdapter,
        workspaceID: Workspace.ID,
        sourcePaneID: PaneID,
        movedTabID: TabID
    ) -> WindowFeature.Action {
        adapter.action(
            for: .splitTab(
                tabID: movedTabID,
                sourcePaneID: sourcePaneID,
                sourceIndex: 0,
                targetPaneID: sourcePaneID,
                orientation: .horizontal,
                insertion: .after
            ),
            workspaceID: workspaceID
        )
    }

    func assertExpectedSplitLayout(
        _ root: WindowFeature.WorkspaceLayoutNode?,
        sourcePaneID: PaneID,
        movedTabID: TabID,
        newPaneID: PaneID
    ) {
        guard case .split(let split)? = root else {
            Issue.record("Expected split layout after adapter-driven split gesture.")
            return
        }

        #expect(split.orientation == .horizontal)
        #expect(split.dividerPosition == 0.5)
        #expect(split.first.paneLayout(for: sourcePaneID)?.tabIDs.isEmpty == true)
        #expect(split.second.paneLayout(for: newPaneID)?.tabIDs == [movedTabID])
        #expect(split.second.paneLayout(for: newPaneID)?.selectedTabID == movedTabID)
    }
}
