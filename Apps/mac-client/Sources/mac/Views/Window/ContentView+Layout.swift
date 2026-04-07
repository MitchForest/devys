// ContentView+Layout.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics
import Split
import Workspace

@MainActor
extension ContentView {
    func saveDefaultLayout() {
        guard workspaceCatalog.hasRepositories else { return }
        let tree = controller.treeSnapshot()
        let layout = PanelLayout(tree: panelNode(from: tree))
        layoutPersistenceService.saveDefaultLayout(layout)
    }

    func applyLayout(_ layout: PanelLayout) {
        guard let rootPane = controller.allPaneIds.first else { return }
        buildLayoutNode(layout.tree, in: rootPane)
        applySplitRatios(from: layout.tree, using: controller.treeSnapshot())
    }

    private func buildLayoutNode(_ node: PanelNode, in paneId: PaneID) {
        switch node {
        case .pane:
            return
        case .split(let orientation, let children, _):
            guard children.count == 2 else { return }
            let splitOrientation: Split.SplitOrientation = orientation == .horizontal ? .horizontal : .vertical
            guard let newPane = controller.splitPane(paneId, orientation: splitOrientation) else { return }
            buildLayoutNode(children[0], in: paneId)
            buildLayoutNode(children[1], in: newPane)
        }
    }

    private func applySplitRatios(from node: PanelNode, using tree: ExternalTreeNode) {
        guard case .split(let orientation, let children, let ratios) = node,
              case .split(let split) = tree,
              children.count == 2 else { return }

        let matches = (orientation == .horizontal && split.orientation == "horizontal")
            || (orientation == .vertical && split.orientation == "vertical")
        if matches {
            let ratio = normalizedRatio(from: ratios)
            if let splitId = UUID(uuidString: split.id) {
                controller.setDividerPosition(ratio, forSplit: splitId, fromExternal: true)
            }
        }

        applySplitRatios(from: children[0], using: split.first)
        applySplitRatios(from: children[1], using: split.second)
    }

    private func panelNode(from node: ExternalTreeNode) -> PanelNode {
        switch node {
        case .pane:
            return .pane(.empty)
        case .split(let split):
            let ratio = CGFloat(split.dividerPosition)
            return .split(
                orientation: split.orientation == "horizontal" ? .horizontal : .vertical,
                children: [panelNode(from: split.first), panelNode(from: split.second)],
                ratios: [ratio, max(0, 1 - ratio)]
            )
        }
    }

    private func normalizedRatio(from ratios: [CGFloat]) -> CGFloat {
        guard ratios.count >= 2 else { return 0.5 }
        let total = ratios[0] + ratios[1]
        guard total > 0 else { return 0.5 }
        return min(max(ratios[0] / total, 0.1), 0.9)
    }
}
