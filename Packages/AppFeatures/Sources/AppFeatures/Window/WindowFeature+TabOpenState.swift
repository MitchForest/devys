import Foundation
import Split
import Workspace

extension WindowFeature.State {
    mutating func openWorkspaceContent(
        workspaceID: Workspace.ID,
        paneID: PaneID,
        content: WorkspaceTabContent,
        mode: WindowFeature.TabOpenMode
    ) -> TabID? {
        var shell = workspaceShells[workspaceID]
            ?? WindowFeature.WorkspaceShell(activeSidebar: activeSidebar)
        var layout = shell.layout ?? WindowFeature.WorkspaceLayout()
        let targetPaneID = layout.paneLayout(for: paneID)?.id
            ?? shell.focusedPaneID
            ?? layout.focusedFallbackPaneID

        guard let targetPaneID,
              layout.paneLayout(for: targetPaneID) != nil else {
            return nil
        }

        if let previewTabID = promotedPreviewTabID(
            in: targetPaneID,
            content: content,
            mode: mode,
            shell: shell,
            layout: layout
        ) {
            layout = workspaceLayoutSettingPreviewTabID(nil, in: targetPaneID, layout: layout)
            return applyOpenedWorkspaceTab(
                previewTabID,
                workspaceID: workspaceID,
                paneID: targetPaneID,
                shell: shell,
                layout: layout
            )
        }

        if let existingTabID = tabID(matching: content, in: shell.tabContents),
           let existingPaneID = paneContaining(tabID: existingTabID, in: layout) {
            return applyOpenedWorkspaceTab(
                existingTabID,
                workspaceID: workspaceID,
                paneID: existingPaneID,
                shell: shell,
                layout: layout
            )
        }

        let openedTabID = insertOrReuseWorkspaceTab(
            in: targetPaneID,
            content: content,
            mode: mode,
            shell: &shell,
            layout: &layout
        )
        return applyOpenedWorkspaceTab(
            openedTabID,
            workspaceID: workspaceID,
            paneID: targetPaneID,
            shell: shell,
            layout: layout
        )
    }

    func tabID(
        matching content: WorkspaceTabContent,
        in tabContents: [TabID: WorkspaceTabContent]
    ) -> TabID? {
        tabContents.first { $0.value.matchesSemanticIdentity(as: content) }?.key
    }

    func paneContaining(
        tabID: TabID,
        in layout: WindowFeature.WorkspaceLayout
    ) -> PaneID? {
        layout.allPaneIDs.first { paneID in
            layout.paneLayout(for: paneID)?.tabIDs.contains(tabID) == true
        }
    }

    private func promotedPreviewTabID(
        in paneID: PaneID,
        content: WorkspaceTabContent,
        mode: WindowFeature.TabOpenMode,
        shell: WindowFeature.WorkspaceShell,
        layout: WindowFeature.WorkspaceLayout
    ) -> TabID? {
        guard mode == .permanent,
              let previewTabID = layout.paneLayout(for: paneID)?.previewTabID,
              let previewContent = shell.tabContents[previewTabID],
              previewContent.matchesSemanticIdentity(as: content) else {
            return nil
        }
        return previewTabID
    }

    private mutating func applyOpenedWorkspaceTab(
        _ tabID: TabID,
        workspaceID: Workspace.ID,
        paneID: PaneID,
        shell: WindowFeature.WorkspaceShell,
        layout: WindowFeature.WorkspaceLayout
    ) -> TabID {
        var shell = shell
        var layout = layout
        layout.selectTab(tabID, in: paneID)
        shell.layout = layout
        shell.focusedPaneID = paneID
        workspaceShells[workspaceID] = shell
        if selectedWorkspaceID == workspaceID {
            selectedTabID = tabID
        }
        return tabID
    }

    private func insertOrReuseWorkspaceTab(
        in paneID: PaneID,
        content: WorkspaceTabContent,
        mode: WindowFeature.TabOpenMode,
        shell: inout WindowFeature.WorkspaceShell,
        layout: inout WindowFeature.WorkspaceLayout
    ) -> TabID {
        if mode == .preview,
           let previewTabID = layout.paneLayout(for: paneID)?.previewTabID {
            shell.tabContents[previewTabID] = content
            return previewTabID
        }

        let newTabID = TabID()
        shell.tabContents[newTabID] = content
        layout.insertTab(newTabID, into: paneID, at: nil, isPreview: mode == .preview)
        return newTabID
    }
}
