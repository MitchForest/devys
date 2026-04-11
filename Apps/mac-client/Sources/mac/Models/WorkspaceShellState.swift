// WorkspaceShellState.swift
// Devys - In-memory workspace-owned shell runtime.

import Foundation
import Split
import Git
import Workspace

@MainActor
final class WorkspaceShellState {
    let workspaceID: Workspace.ID
    var sidebarMode: WorkspaceSidebarMode
    var gitStore: GitStore?
    var agentRuntimeRegistry: WorkspaceAgentRuntimeRegistry
    var editorSessions: [TabID: EditorSession]
    var editorSessionPool: EditorSessionPool
    var controller: DevysSplitController
    var tabContents: [TabID: TabContent]
    var selectedTabId: TabID?
    var previewTabId: TabID?
    var closeBypass: Set<TabID>
    var closeInFlight: Set<TabID>

    init(
        workspaceID: Workspace.ID,
        sidebarMode: WorkspaceSidebarMode = .files,
        gitStore: GitStore? = nil,
        agentRuntimeRegistry: WorkspaceAgentRuntimeRegistry = WorkspaceAgentRuntimeRegistry(),
        editorSessions: [TabID: EditorSession] = [:],
        editorSessionPool: EditorSessionPool = EditorSessionPool(),
        controller: DevysSplitController,
        tabContents: [TabID: TabContent] = [:],
        selectedTabId: TabID? = nil,
        previewTabId: TabID? = nil,
        closeBypass: Set<TabID> = [],
        closeInFlight: Set<TabID> = []
    ) {
        self.workspaceID = workspaceID
        self.sidebarMode = sidebarMode
        self.gitStore = gitStore
        self.agentRuntimeRegistry = agentRuntimeRegistry
        self.editorSessions = editorSessions
        self.editorSessionPool = editorSessionPool
        self.controller = controller
        self.tabContents = tabContents
        self.selectedTabId = selectedTabId
        self.previewTabId = previewTabId
        self.closeBypass = closeBypass
        self.closeInFlight = closeInFlight
    }
}
