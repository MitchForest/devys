import Foundation
import Split

extension WindowFeature.WorkspaceLayout {
    mutating func insertTab(
        _ tabID: TabID,
        into paneID: PaneID,
        at index: Int?,
        isPreview: Bool
    ) {
        _ = root.insertTab(tabID, into: paneID, at: index, isPreview: isPreview)
    }

    mutating func selectTab(_ tabID: TabID, in paneID: PaneID) {
        _ = root.selectTab(tabID, in: paneID)
    }

    mutating func closeTab(
        _ tabID: TabID,
        in paneID: PaneID
    ) -> PaneID? {
        let emptyPaneID = root.closeTab(tabID, in: paneID, totalPaneCount: allPaneIDs.count)
        guard let emptyPaneID else { return nil }
        return closePane(emptyPaneID)
    }

    mutating func reorderTab(
        _ tabID: TabID,
        in paneID: PaneID,
        from sourceIndex: Int,
        to destinationIndex: Int
    ) {
        _ = root.reorderTab(
            tabID,
            in: paneID,
            from: sourceIndex,
            to: destinationIndex
        )
    }

    mutating func moveTab(
        _ tabID: TabID,
        from sourcePaneID: PaneID,
        to destinationPaneID: PaneID,
        at index: Int?
    ) -> PaneID? {
        let emptyPaneID = root.moveTab(
            tabID,
            from: sourcePaneID,
            to: destinationPaneID,
            at: index,
            totalPaneCount: allPaneIDs.count,
            preserveEmptySourcePane: false
        )
        guard let emptyPaneID else { return nil }
        return closePane(emptyPaneID)
    }

    mutating func splitPane(
        _ paneID: PaneID,
        newPaneID: PaneID,
        orientation: Split.SplitOrientation,
        insertion: WindowFeature.SplitInsertionPosition
    ) {
        root = root.splittingPane(
            paneID,
            newPaneID: newPaneID,
            orientation: orientation,
            insertion: insertion
        )
    }

    mutating func splitPaneWithTab(
        targetPaneID: PaneID,
        newPaneID: PaneID,
        tabID: TabID,
        sourcePaneID: PaneID,
        orientation: Split.SplitOrientation,
        insertion: WindowFeature.SplitInsertionPosition
    ) -> PaneID? {
        root = root.splittingPane(
            targetPaneID,
            newPaneID: newPaneID,
            orientation: orientation,
            insertion: insertion
        )

        let emptyPaneID = root.moveTab(
            tabID,
            from: sourcePaneID,
            to: newPaneID,
            at: nil,
            totalPaneCount: allPaneIDs.count,
            preserveEmptySourcePane: sourcePaneID == targetPaneID
        )

        guard let emptyPaneID else { return newPaneID }
        if emptyPaneID == targetPaneID {
            return newPaneID
        }
        _ = closePane(emptyPaneID)
        return newPaneID
    }

    mutating func closePane(_ paneID: PaneID) -> PaneID? {
        guard allPaneIDs.count > 1 else { return nil }
        let result = root.closingPane(paneID)
        guard let node = result.node else { return nil }
        root = node
        return result.focusedPaneID
    }

    mutating func setDividerPosition(_ position: Double, splitID: UUID) {
        _ = root.setDividerPosition(position, splitID: splitID)
    }
}

private extension WindowFeature.WorkspaceLayoutNode {
    var firstPaneID: PaneID? {
        switch self {
        case .pane(let pane):
            return pane.id
        case .split(let split):
            return split.first.firstPaneID ?? split.second.firstPaneID
        }
    }

    mutating func insertTab(
        _ tabID: TabID,
        into paneID: PaneID,
        at index: Int?,
        isPreview: Bool
    ) -> Bool {
        switch self {
        case .pane(var pane):
            guard pane.id == paneID else { return false }
            let insertionIndex = max(0, min(index ?? pane.tabIDs.count, pane.tabIDs.count))
            pane.tabIDs.insert(tabID, at: insertionIndex)
            pane.selectedTabID = tabID
            if isPreview {
                pane.previewTabID = tabID
            }
            self = .pane(pane)
            return true

        case .split(var split):
            if split.first.insertTab(tabID, into: paneID, at: index, isPreview: isPreview) {
                self = .split(split)
                return true
            }
            let inserted = split.second.insertTab(tabID, into: paneID, at: index, isPreview: isPreview)
            self = .split(split)
            return inserted
        }
    }

    mutating func selectTab(_ tabID: TabID, in paneID: PaneID) -> Bool {
        switch self {
        case .pane(var pane):
            guard pane.id == paneID, pane.tabIDs.contains(tabID) else { return false }
            pane.selectedTabID = tabID
            self = .pane(pane)
            return true

        case .split(var split):
            if split.first.selectTab(tabID, in: paneID) {
                self = .split(split)
                return true
            }
            let selected = split.second.selectTab(tabID, in: paneID)
            self = .split(split)
            return selected
        }
    }

    mutating func closeTab(
        _ tabID: TabID,
        in paneID: PaneID,
        totalPaneCount: Int
    ) -> PaneID? {
        switch self {
        case .pane(var pane):
            guard pane.id == paneID,
                  let removedIndex = pane.tabIDs.firstIndex(of: tabID) else {
                return nil
            }

            pane.tabIDs.remove(at: removedIndex)
            if pane.previewTabID == tabID {
                pane.previewTabID = nil
            }

            if pane.selectedTabID == tabID {
                if pane.tabIDs.indices.contains(removedIndex) {
                    pane.selectedTabID = pane.tabIDs[removedIndex]
                } else {
                    pane.selectedTabID = pane.tabIDs.last
                }
            }

            self = .pane(pane)
            guard pane.tabIDs.isEmpty, totalPaneCount > 1 else {
                return nil
            }
            return pane.id

        case .split(var split):
            if let emptyPaneID = split.first.closeTab(tabID, in: paneID, totalPaneCount: totalPaneCount) {
                self = .split(split)
                return emptyPaneID
            }
            let emptyPaneID = split.second.closeTab(tabID, in: paneID, totalPaneCount: totalPaneCount)
            self = .split(split)
            return emptyPaneID
        }
    }

    mutating func reorderTab(
        _ tabID: TabID,
        in paneID: PaneID,
        from sourceIndex: Int,
        to destinationIndex: Int
    ) -> Bool {
        switch self {
        case .pane(var pane):
            guard pane.id == paneID,
                  pane.tabIDs.indices.contains(sourceIndex),
                  pane.tabIDs[sourceIndex] == tabID,
                  destinationIndex >= 0,
                  destinationIndex <= pane.tabIDs.count else {
                return false
            }

            if sourceIndex == destinationIndex
                || sourceIndex + 1 == destinationIndex {
                return true
            }

            let tabID = pane.tabIDs.remove(at: sourceIndex)
            let adjustedIndex = destinationIndex > sourceIndex
                ? destinationIndex - 1
                : destinationIndex
            pane.tabIDs.insert(tabID, at: adjustedIndex)
            self = .pane(pane)
            return true

        case .split(var split):
            if split.first.reorderTab(tabID, in: paneID, from: sourceIndex, to: destinationIndex) {
                self = .split(split)
                return true
            }
            let reordered = split.second.reorderTab(
                tabID,
                in: paneID,
                from: sourceIndex,
                to: destinationIndex
            )
            self = .split(split)
            return reordered
        }
    }

    mutating func moveTab(
        _ tabID: TabID,
        from sourcePaneID: PaneID,
        to destinationPaneID: PaneID,
        at index: Int?,
        totalPaneCount: Int,
        preserveEmptySourcePane: Bool
    ) -> PaneID? {
        let previewTabID = removeTab(
            tabID,
            from: sourcePaneID,
            totalPaneCount: totalPaneCount,
            preserveEmptySourcePane: preserveEmptySourcePane
        )
        guard insertMovedTab(
            tabID,
            into: destinationPaneID,
            at: index,
            previewTabID: previewTabID
        ) else {
            return nil
        }
        return previewTabID == .paneBecameEmpty ? sourcePaneID : nil
    }

    mutating func setDividerPosition(_ position: Double, splitID: UUID) -> Bool {
        switch self {
        case .pane:
            return false

        case .split(var split):
            if split.id == splitID {
                split.dividerPosition = min(max(position, 0.1), 0.9)
                self = .split(split)
                return true
            }
            if split.first.setDividerPosition(position, splitID: splitID) {
                self = .split(split)
                return true
            }
            let updated = split.second.setDividerPosition(position, splitID: splitID)
            self = .split(split)
            return updated
        }
    }

    func splittingPane(
        _ paneID: PaneID,
        newPaneID: PaneID,
        orientation: Split.SplitOrientation,
        insertion: WindowFeature.SplitInsertionPosition
    ) -> Self {
        switch self {
        case .pane(let pane):
            guard pane.id == paneID else { return self }
            let newPane = WindowFeature.WorkspacePaneLayout(id: newPaneID)
            let split = WindowFeature.WorkspaceSplitLayout(
                orientation: orientation,
                dividerPosition: 0.5,
                first: insertion == .before ? .pane(newPane) : .pane(pane),
                second: insertion == .before ? .pane(pane) : .pane(newPane)
            )
            return .split(split)

        case .split(var split):
            split.first = split.first.splittingPane(
                paneID,
                newPaneID: newPaneID,
                orientation: orientation,
                insertion: insertion
            )
            split.second = split.second.splittingPane(
                paneID,
                newPaneID: newPaneID,
                orientation: orientation,
                insertion: insertion
            )
            return .split(split)
        }
    }

    func closingPane(_ paneID: PaneID) -> (node: Self?, focusedPaneID: PaneID?) {
        switch self {
        case .pane(let pane):
            if pane.id == paneID {
                return (nil, nil)
            }
            return (self, nil)

        case .split(let split):
            if case .pane(let firstPane) = split.first, firstPane.id == paneID {
                return (split.second, split.second.firstPaneID)
            }
            if case .pane(let secondPane) = split.second, secondPane.id == paneID {
                return (split.first, split.first.firstPaneID)
            }

            let firstResult = split.first.closingPane(paneID)
            if firstResult.node == nil {
                return (split.second, split.second.firstPaneID)
            }

            let secondResult = split.second.closingPane(paneID)
            if secondResult.node == nil {
                return (split.first, split.first.firstPaneID)
            }

            guard let firstNode = firstResult.node,
                  let secondNode = secondResult.node else {
                return (self, nil)
            }

            var updated = split
            updated.first = firstNode
            updated.second = secondNode
            return (.split(updated), firstResult.focusedPaneID ?? secondResult.focusedPaneID)
        }
    }

    private enum RemovedPreviewState: Equatable {
        case none
        case previewTab(TabID)
        case paneBecameEmpty
    }

    private mutating func removeTab(
        _ tabID: TabID,
        from paneID: PaneID,
        totalPaneCount: Int,
        preserveEmptySourcePane: Bool
    ) -> RemovedPreviewState {
        switch self {
        case .pane(var pane):
            guard pane.id == paneID,
                  let removedIndex = pane.tabIDs.firstIndex(of: tabID) else {
                return .none
            }

            pane.tabIDs.remove(at: removedIndex)
            let removedPreview = pane.previewTabID == tabID
            if removedPreview {
                pane.previewTabID = nil
            }
            if pane.selectedTabID == tabID {
                if pane.tabIDs.indices.contains(removedIndex) {
                    pane.selectedTabID = pane.tabIDs[removedIndex]
                } else {
                    pane.selectedTabID = pane.tabIDs.last
                }
            }

            self = .pane(pane)
            if pane.tabIDs.isEmpty,
               totalPaneCount > 1,
               !preserveEmptySourcePane {
                return .paneBecameEmpty
            }
            return removedPreview ? .previewTab(tabID) : .none

        case .split(var split):
            let firstState = split.first.removeTab(
                tabID,
                from: paneID,
                totalPaneCount: totalPaneCount,
                preserveEmptySourcePane: preserveEmptySourcePane
            )
            if firstState != .none {
                self = .split(split)
                return firstState
            }
            let secondState = split.second.removeTab(
                tabID,
                from: paneID,
                totalPaneCount: totalPaneCount,
                preserveEmptySourcePane: preserveEmptySourcePane
            )
            self = .split(split)
            return secondState
        }
    }

    private mutating func insertMovedTab(
        _ tabID: TabID,
        into paneID: PaneID,
        at index: Int?,
        previewTabID: RemovedPreviewState
    ) -> Bool {
        switch self {
        case .pane(var pane):
            guard pane.id == paneID else { return false }
            let insertionIndex = max(0, min(index ?? pane.tabIDs.count, pane.tabIDs.count))
            pane.tabIDs.insert(tabID, at: insertionIndex)
            pane.selectedTabID = tabID
            if case .previewTab(let previewTabID) = previewTabID {
                pane.previewTabID = previewTabID
            }
            self = .pane(pane)
            return true

        case .split(var split):
            if split.first.insertMovedTab(tabID, into: paneID, at: index, previewTabID: previewTabID) {
                self = .split(split)
                return true
            }
            let inserted = split.second.insertMovedTab(
                tabID,
                into: paneID,
                at: index,
                previewTabID: previewTabID
            )
            self = .split(split)
            return inserted
        }
    }
}
