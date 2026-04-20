import Dependencies
import Foundation
import RemoteCore

public struct RemoteRepositoryPersistenceClient: Sendable {
    public var load: @Sendable () async throws -> [RemoteRepositoryAuthority]
    public var save: @Sendable ([RemoteRepositoryAuthority]) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> [RemoteRepositoryAuthority],
        save: @escaping @Sendable ([RemoteRepositoryAuthority]) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }
}

extension RemoteRepositoryPersistenceClient: DependencyKey {
    public static let liveValue = Self(
        load: { [] },
        save: { _ in }
    )
}

extension RemoteRepositoryPersistenceClient: TestDependencyKey {
    public static let testValue = Self(
        load: { [] },
        save: { _ in }
    )
}

public extension DependencyValues {
    var remoteRepositoryPersistenceClient: RemoteRepositoryPersistenceClient {
        get { self[RemoteRepositoryPersistenceClient.self] }
        set { self[RemoteRepositoryPersistenceClient.self] = newValue }
    }
}
