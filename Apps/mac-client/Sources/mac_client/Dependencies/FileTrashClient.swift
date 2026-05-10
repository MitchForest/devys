import ComposableArchitecture
import Foundation

struct FileTrashClient: Sendable {
    var moveToTrash: @Sendable (URL) async throws -> Void

    init(moveToTrash: @escaping @Sendable (URL) async throws -> Void) {
        self.moveToTrash = moveToTrash
    }
}

private enum FileTrashClientKey: DependencyKey {
    static let liveValue = FileTrashClient { _ in }
}

extension DependencyValues {
    var fileTrashClient: FileTrashClient {
        get { self[FileTrashClientKey.self] }
        set { self[FileTrashClientKey.self] = newValue }
    }
}
