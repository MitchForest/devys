import Foundation

extension DevysSplitController {
    @discardableResult
    func dispatchGestureIntent(_ intent: SplitGestureIntent) -> Bool {
        if delegate?.splitView(self, didRequest: intent) == true {
            return true
        }

        performGestureIntentFallback(intent)
        return false
    }

    private func performGestureIntentFallback(_ intent: SplitGestureIntent) {
        switch intent {
        case let .reorderTab(tabID, paneID, _, destinationIndex):
            reorderTab(tabID, inPane: paneID, toIndex: destinationIndex)

        case let .moveTab(tabID, sourcePaneID, _, destinationPaneID, destinationIndex):
            guard let tab = tab(tabID) else { return }
            moveTab(
                tab,
                from: sourcePaneID,
                to: destinationPaneID,
                atIndex: destinationIndex
            )

        case let .splitPane(paneID, orientation, _):
            _ = splitPane(paneID, orientation: orientation)

        case let .splitTab(
            tabID,
            sourcePaneID,
            _,
            targetPaneID,
            orientation,
            insertion
        ):
            guard let tab = tab(tabID) else { return }
            _ = splitPaneWithTab(
                targetPaneID,
                orientation: orientation,
                tab: tab,
                insertFirst: insertion == .before,
                from: sourcePaneID
            )

        case let .closePane(paneID):
            _ = closePane(paneID)
        }
    }
}
