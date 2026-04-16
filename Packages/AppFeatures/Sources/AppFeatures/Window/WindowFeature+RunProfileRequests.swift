import Foundation
import Workspace

public extension WindowFeature {
    enum RunProfileLaunchResolution: Equatable, Sendable {
        case ready(RunProfileLaunchRequest)
        case failed(String)
    }

    struct RunProfileLaunchRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let workspaceID: Workspace.ID
        public let resolvedProfile: ResolvedStartupProfile

        public init(
            workspaceID: Workspace.ID,
            resolvedProfile: ResolvedStartupProfile,
            id: UUID = UUID()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.resolvedProfile = resolvedProfile
        }
    }

    struct RunProfileLaunchResult: Equatable, Sendable {
        public let workspaceID: Workspace.ID
        public let profileID: StartupProfile.ID
        public let terminalIDs: [UUID]
        public let backgroundProcessIDs: [UUID]
        public let failures: [String]

        public init(
            workspaceID: Workspace.ID,
            profileID: StartupProfile.ID,
            terminalIDs: [UUID],
            backgroundProcessIDs: [UUID],
            failures: [String]
        ) {
            self.workspaceID = workspaceID
            self.profileID = profileID
            self.terminalIDs = terminalIDs
            self.backgroundProcessIDs = backgroundProcessIDs
            self.failures = failures
        }
    }

    struct RunProfileStopRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let workspaceID: Workspace.ID
        public let terminalIDs: [UUID]
        public let backgroundProcessIDs: [UUID]

        public init(
            workspaceID: Workspace.ID,
            terminalIDs: [UUID],
            backgroundProcessIDs: [UUID],
            id: UUID = UUID()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.terminalIDs = terminalIDs
            self.backgroundProcessIDs = backgroundProcessIDs
        }
    }
}
