import Foundation

struct WorkspaceTab: Equatable, Identifiable, Sendable {
    typealias ID = UUID

    let id: ID
    var kind: WindowTabKind
    var projectRootURL: URL?

    init(
        id: ID,
        kind: WindowTabKind,
        projectRootURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.projectRootURL = projectRootURL?.standardizedFileURL
    }
}
