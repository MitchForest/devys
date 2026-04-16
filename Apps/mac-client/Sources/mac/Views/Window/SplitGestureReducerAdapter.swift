import AppFeatures
import Foundation
import Split
import Workspace

struct SplitGestureReducerAdapter {
    var makePaneID: @MainActor () -> PaneID = { PaneID() }

    @MainActor
    func action(
        for intent: SplitGestureIntent,
        workspaceID: Workspace.ID
    ) -> WindowFeature.Action {
        switch intent {
        case let .reorderTab(tabID, paneID, sourceIndex, destinationIndex):
            return .reorderWorkspaceTab(
                workspaceID: workspaceID,
                paneID: paneID,
                tabID: tabID,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex
            )

        case let .moveTab(tabID, sourcePaneID, _, destinationPaneID, destinationIndex):
            return .moveWorkspaceTab(
                workspaceID: workspaceID,
                tabID: tabID,
                sourcePaneID: sourcePaneID,
                destinationPaneID: destinationPaneID,
                index: destinationIndex
            )

        case let .splitPane(paneID, orientation, insertion):
            return .splitWorkspacePane(
                workspaceID: workspaceID,
                paneID: paneID,
                newPaneID: makePaneID(),
                orientation: orientation,
                insertion: insertion.windowInsertionPosition
            )

        case let .splitTab(
            tabID,
            sourcePaneID,
            sourceIndex,
            targetPaneID,
            orientation,
            insertion
        ):
            return .splitWorkspacePaneWithTab(
                workspaceID: workspaceID,
                targetPaneID: targetPaneID,
                newPaneID: makePaneID(),
                tabID: tabID,
                sourcePaneID: sourcePaneID,
                sourceIndex: sourceIndex,
                orientation: orientation,
                insertion: insertion.windowInsertionPosition
            )

        case let .closePane(paneID):
            return .closeWorkspacePane(workspaceID: workspaceID, paneID: paneID)
        }
    }
}

extension SplitInsertionPosition {
    var windowInsertionPosition: WindowFeature.SplitInsertionPosition {
        switch self {
        case .before:
            return .before
        case .after:
            return .after
        }
    }
}
