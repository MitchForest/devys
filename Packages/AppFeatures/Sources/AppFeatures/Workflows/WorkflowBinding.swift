import Foundation
import Workspace

public struct WorkflowTerminalBinding: Equatable, Sendable {
    public let workspaceID: Workspace.ID
    public let runID: UUID
    public let nodeID: String
    public let attemptID: UUID
    public let nodeTitle: String
    public let definitionName: String
    public let isActive: Bool

    public init(
        workspaceID: Workspace.ID,
        runID: UUID,
        nodeID: String,
        attemptID: UUID,
        nodeTitle: String,
        definitionName: String,
        isActive: Bool
    ) {
        self.workspaceID = workspaceID
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.nodeTitle = nodeTitle
        self.definitionName = definitionName
        self.isActive = isActive
    }
}
