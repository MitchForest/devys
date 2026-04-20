import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Runtime Selection Sync Tests")
struct WorkspaceRuntimeSelectionSyncTests {
    @Test("Local selection restores the runtime when no visible workspace is active")
    func localSelectionWithoutVisibleRuntimeRestoresSelection() {
        let workspaceID = "/tmp/devys/worktrees/feat-ssh"

        #expect(
            workspaceRuntimeSyncDecision(
                for: WorkspaceRuntimeSyncSnapshot(
                    isRemoteWorkspaceSelected: false,
                    selectedWorkspaceID: workspaceID,
                    selectedCatalogWorktreeID: workspaceID,
                    visibleWorkspaceID: nil,
                    hasRuntimeForSelectedWorkspace: false
                )
            ) == .restoreSelectedWorkspace
        )
    }

    @Test("Visible local runtime stays put when it already matches reducer selection")
    func matchingVisibleRuntimeNeedsNoSync() {
        let workspaceID = "/tmp/devys/worktrees/feat-ssh"

        #expect(
            workspaceRuntimeSyncDecision(
                for: WorkspaceRuntimeSyncSnapshot(
                    isRemoteWorkspaceSelected: false,
                    selectedWorkspaceID: workspaceID,
                    selectedCatalogWorktreeID: workspaceID,
                    visibleWorkspaceID: workspaceID,
                    hasRuntimeForSelectedWorkspace: true
                )
            ) == .none
        )
    }

    @Test("Reducer selection waits for catalog hydration before touching runtime state")
    func missingCatalogWorktreeDefersSync() {
        let workspaceID = "/tmp/devys/worktrees/feat-ssh"

        #expect(
            workspaceRuntimeSyncDecision(
                for: WorkspaceRuntimeSyncSnapshot(
                    isRemoteWorkspaceSelected: false,
                    selectedWorkspaceID: workspaceID,
                    selectedCatalogWorktreeID: nil,
                    visibleWorkspaceID: nil,
                    hasRuntimeForSelectedWorkspace: false
                )
            ) == .none
        )
    }

    @Test("Dropping local selection tears down a stale visible runtime")
    func emptyLocalSelectionDeactivatesVisibleRuntime() {
        #expect(
            workspaceRuntimeSyncDecision(
                for: WorkspaceRuntimeSyncSnapshot(
                    isRemoteWorkspaceSelected: false,
                    selectedWorkspaceID: nil,
                    selectedCatalogWorktreeID: nil,
                    visibleWorkspaceID: "/tmp/devys/worktrees/feat-ssh",
                    hasRuntimeForSelectedWorkspace: false
                )
            ) == .deactivateVisibleWorkspace
        )
    }

    @Test("Remote selection deactivates any lingering local runtime")
    func remoteSelectionDeactivatesVisibleLocalRuntime() {
        let workspaceID = "/tmp/devys/worktrees/feat-ssh"

        #expect(
            workspaceRuntimeSyncDecision(
                for: WorkspaceRuntimeSyncSnapshot(
                    isRemoteWorkspaceSelected: true,
                    selectedWorkspaceID: workspaceID,
                    selectedCatalogWorktreeID: workspaceID,
                    visibleWorkspaceID: workspaceID,
                    hasRuntimeForSelectedWorkspace: true
                )
            ) == .deactivateVisibleWorkspace
        )
    }
}
