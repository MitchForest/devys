import Foundation

public extension RemoteTerminalFeature.State {
    var worktreeCreationRepository: RemoteRepositoryRecord? {
        guard let worktreeCreationRepositoryID else { return nil }
        return repositories.first { $0.id == worktreeCreationRepositoryID }
    }
}
