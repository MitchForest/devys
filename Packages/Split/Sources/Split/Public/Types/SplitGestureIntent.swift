import Foundation

/// Reducer-meaningful shell mutations requested by live split gestures.
public enum SplitGestureIntent: Equatable, Sendable {
    case reorderTab(
        tabID: TabID,
        paneID: PaneID,
        sourceIndex: Int,
        destinationIndex: Int
    )
    case moveTab(
        tabID: TabID,
        sourcePaneID: PaneID,
        sourceIndex: Int,
        destinationPaneID: PaneID,
        destinationIndex: Int?
    )
    case splitPane(
        paneID: PaneID,
        orientation: SplitOrientation,
        insertion: SplitInsertionPosition
    )
    case splitTab(
        tabID: TabID,
        sourcePaneID: PaneID,
        sourceIndex: Int,
        targetPaneID: PaneID,
        orientation: SplitOrientation,
        insertion: SplitInsertionPosition
    )
    case closePane(paneID: PaneID)
}
