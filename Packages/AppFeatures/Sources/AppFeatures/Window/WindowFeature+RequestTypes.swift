import Foundation
import RemoteCore
import Split
import Workspace

public extension WindowFeature {
    struct FocusChatSessionRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var sessionID: ChatSessionID

        public init(
            workspaceID: Workspace.ID,
            sessionID: ChatSessionID,
            id: UUID = UUID()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.sessionID = sessionID
        }
    }

    struct WindowRelaunchRestoreRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var snapshot: WindowRelaunchSnapshot
        public var settings: RelaunchSettingsSnapshot

        public init(
            snapshot: WindowRelaunchSnapshot,
            settings: RelaunchSettingsSnapshot,
            id: UUID = UUID()
        ) {
            self.id = id
            self.snapshot = snapshot
            self.settings = settings
        }
    }

    struct RemoteWorkspaceTransitionRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var sourceWorkspaceID: Workspace.ID?
        public var targetRepositoryID: RemoteRepositoryAuthority.ID
        public var targetWorkspaceID: Workspace.ID
        public var shouldPersistVisibleWorkspaceState: Bool
        public var shouldResetHostWorkspaceState: Bool

        public init(
            sourceWorkspaceID: Workspace.ID? = nil,
            targetRepositoryID: RemoteRepositoryAuthority.ID,
            targetWorkspaceID: Workspace.ID,
            shouldPersistVisibleWorkspaceState: Bool,
            shouldResetHostWorkspaceState: Bool,
            id: UUID = UUID()
        ) {
            self.id = id
            self.sourceWorkspaceID = sourceWorkspaceID
            self.targetRepositoryID = targetRepositoryID
            self.targetWorkspaceID = targetWorkspaceID
            self.shouldPersistVisibleWorkspaceState = shouldPersistVisibleWorkspaceState
            self.shouldResetHostWorkspaceState = shouldResetHostWorkspaceState
        }
    }

    struct RemoteTerminalLaunchRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var attachCommand: String
        public var preferredPaneID: PaneID?

        public init(
            workspaceID: Workspace.ID,
            attachCommand: String,
            preferredPaneID: PaneID? = nil,
            id: UUID = UUID()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.attachCommand = attachCommand
            self.preferredPaneID = preferredPaneID
        }
    }

    struct RemoteWorktreeCreationResult: Equatable, Sendable {
        public var createdWorktree: RemoteWorktree
        public var worktrees: [RemoteWorktree]

        public init(
            createdWorktree: RemoteWorktree,
            worktrees: [RemoteWorktree]
        ) {
            self.createdWorktree = createdWorktree
            self.worktrees = worktrees
        }
    }
}
