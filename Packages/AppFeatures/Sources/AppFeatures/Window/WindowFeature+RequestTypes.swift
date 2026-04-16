import Foundation
import Workspace

public extension WindowFeature {
    struct FocusAgentSessionRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var sessionID: AgentSessionID

        public init(
            workspaceID: Workspace.ID,
            sessionID: AgentSessionID,
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
}
