import Foundation
import Split

public extension WindowFeature {
    struct WorkspaceTabCloseContext: Equatable, Sendable {
        public var tabID: TabID
        public var paneID: PaneID
        public var content: WorkspaceTabContent
        public var isDirtyEditor: Bool

        public init(
            tabID: TabID,
            paneID: PaneID,
            content: WorkspaceTabContent,
            isDirtyEditor: Bool
        ) {
            self.tabID = tabID
            self.paneID = paneID
            self.content = content
            self.isDirtyEditor = isDirtyEditor
        }
    }

    struct WorkspaceTabCloseRequest: Equatable, Identifiable, Sendable {
        public enum Strategy: Equatable, Sendable {
            case closeImmediately
            case confirmDirtyEditor(fileName: String)
        }

        public let id: UUID
        public var context: WorkspaceTabCloseContext
        public var strategy: Strategy

        public init(
            context: WorkspaceTabCloseContext,
            strategy: Strategy,
            id: UUID = UUID()
        ) {
            self.id = id
            self.context = context
            self.strategy = strategy
        }
    }
}
