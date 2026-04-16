// ContentView+Layout.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics
import AppFeatures
import Workspace

@MainActor
extension ContentView {
    func saveDefaultLayout() {
        guard let workspaceID = selectedWorkspaceID,
              let layout = store.workspaceShells[workspaceID]?.layout else {
            return
        }
        layoutPersistenceService.saveDefaultLayout(
            PanelLayout(tree: panelNode(from: layout.root))
        )
    }

    func applyLayout(
        _ layout: PanelLayout,
        workspaceID: Workspace.ID? = nil
    ) {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID else { return }
        let workspaceLayout = WindowFeature.WorkspaceLayout(
            root: workspaceLayoutNode(from: layout.tree)
        )
        store.send(.setWorkspaceLayout(workspaceID: workspaceID, layout: workspaceLayout))
        store.send(
            .setWorkspaceFocusedPaneID(
                workspaceID: workspaceID,
                paneID: workspaceLayout.focusedFallbackPaneID
            )
        )
        renderWorkspaceLayout(for: workspaceID)
    }

    private func panelNode(from node: WindowFeature.WorkspaceLayoutNode) -> PanelNode {
        switch node {
        case .pane:
            return .pane(.empty)
        case .split(let split):
            let ratio = CGFloat(split.dividerPosition)
            return .split(
                orientation: split.orientation == .horizontal ? .horizontal : .vertical,
                children: [
                    panelNode(from: split.first),
                    panelNode(from: split.second)
                ],
                ratios: [ratio, max(0, 1 - ratio)]
            )
        }
    }

    private func workspaceLayoutNode(from node: PanelNode) -> WindowFeature.WorkspaceLayoutNode {
        switch node {
        case .pane:
            return .pane(WindowFeature.WorkspacePaneLayout())

        case .split(let orientation, let children, let ratios):
            guard children.count == 2 else {
                return .pane(WindowFeature.WorkspacePaneLayout())
            }
            return .split(
                WindowFeature.WorkspaceSplitLayout(
                    orientation: orientation == .horizontal ? .horizontal : .vertical,
                    dividerPosition: normalizedRatio(from: ratios),
                    first: workspaceLayoutNode(from: children[0]),
                    second: workspaceLayoutNode(from: children[1])
                )
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
