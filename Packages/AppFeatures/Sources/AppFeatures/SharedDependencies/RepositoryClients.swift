import Dependencies
import Foundation
import Git
import Workspace

public struct RecentRepositoriesClient: Sendable {
    public var load: @MainActor @Sendable () -> [URL]
    public var add: @MainActor @Sendable (URL) -> Void
    public var remove: @MainActor @Sendable (URL) -> Void
    public var clear: @MainActor @Sendable () -> Void

    public init(
        load: @escaping @MainActor @Sendable () -> [URL],
        add: @escaping @MainActor @Sendable (URL) -> Void,
        remove: @escaping @MainActor @Sendable (URL) -> Void,
        clear: @escaping @MainActor @Sendable () -> Void
    ) {
        self.load = load
        self.add = add
        self.remove = remove
        self.clear = clear
    }
}

extension RecentRepositoriesClient: DependencyKey {
    public static let liveValue = Self(
        load: { [] },
        add: { _ in },
        remove: { _ in },
        clear: {}
    )
}

extension RecentRepositoriesClient: TestDependencyKey {
    public static let testValue = Self(
        load: unimplemented("\(Self.self).load", placeholder: []),
        add: unimplemented("\(Self.self).add"),
        remove: unimplemented("\(Self.self).remove"),
        clear: unimplemented("\(Self.self).clear")
    )
}

public extension DependencyValues {
    var recentRepositoriesClient: RecentRepositoriesClient {
        get { self[RecentRepositoriesClient.self] }
        set { self[RecentRepositoriesClient.self] = newValue }
    }
}

public extension RecentRepositoriesClient {
    static func live(service: RecentRepositoriesService) -> Self {
        Self(
            load: { service.load() },
            add: { service.add($0) },
            remove: { service.remove($0) },
            clear: { service.clear() }
        )
    }
}

public struct RepositoryDiscoveryClient: Sendable {
    public var resolveRepository: @Sendable (URL) async throws -> Repository

    public init(
        resolveRepository: @escaping @Sendable (URL) async throws -> Repository
    ) {
        self.resolveRepository = resolveRepository
    }
}

extension RepositoryDiscoveryClient: DependencyKey {
    public static let liveValue = Self { url in
        try await GitRepositoryDiscoveryService().resolveRepository(from: url)
    }
}

extension RepositoryDiscoveryClient: TestDependencyKey {
    public static let testValue = Self(
        resolveRepository: unimplemented("\(Self.self).resolveRepository")
    )
}

public extension DependencyValues {
    var repositoryDiscoveryClient: RepositoryDiscoveryClient {
        get { self[RepositoryDiscoveryClient.self] }
        set { self[RepositoryDiscoveryClient.self] = newValue }
    }
}

public extension RepositoryDiscoveryClient {
    static func live(service: GitRepositoryDiscoveryService) -> Self {
        Self {
            try await service.resolveRepository(from: $0)
        }
    }
}

public struct WorkspaceCreationClient: Sendable {
    public var listBranches: @Sendable (URL) async throws -> [WorkspaceBranchReference]
    public var listPullRequests: @Sendable (URL) async throws -> [PullRequest]
    public var createWorkspace: @Sendable (Repository, WorkspaceCreationRequest) async throws -> Workspace
    public var importWorkspaces: @Sendable ([URL], Repository) async throws -> [Workspace]

    public init(
        listBranches: @escaping @Sendable (URL) async throws -> [WorkspaceBranchReference],
        listPullRequests: @escaping @Sendable (URL) async throws -> [PullRequest],
        createWorkspace: @escaping @Sendable (Repository, WorkspaceCreationRequest) async throws -> Workspace,
        importWorkspaces: @escaping @Sendable ([URL], Repository) async throws -> [Workspace]
    ) {
        self.listBranches = listBranches
        self.listPullRequests = listPullRequests
        self.createWorkspace = createWorkspace
        self.importWorkspaces = importWorkspaces
    }
}

extension WorkspaceCreationClient: DependencyKey {
    public static let liveValue = Self(
        listBranches: { try await WorkspaceCreationService().listBranches(in: $0) },
        listPullRequests: { try await WorkspaceCreationService().listPullRequests(in: $0) },
        createWorkspace: { try await WorkspaceCreationService().createWorkspace(in: $0, request: $1) },
        importWorkspaces: { try await WorkspaceCreationService().importWorkspaces(at: $0, into: $1) }
    )
}

extension WorkspaceCreationClient: TestDependencyKey {
    public static let testValue = Self(
        listBranches: unimplemented("\(Self.self).listBranches", placeholder: []),
        listPullRequests: unimplemented("\(Self.self).listPullRequests", placeholder: []),
        createWorkspace: unimplemented("\(Self.self).createWorkspace"),
        importWorkspaces: unimplemented("\(Self.self).importWorkspaces", placeholder: [])
    )
}

public extension DependencyValues {
    var workspaceCreationClient: WorkspaceCreationClient {
        get { self[WorkspaceCreationClient.self] }
        set { self[WorkspaceCreationClient.self] = newValue }
    }
}

public extension WorkspaceCreationClient {
    static func live(service: WorkspaceCreationService) -> Self {
        Self(
            listBranches: { try await service.listBranches(in: $0) },
            listPullRequests: { try await service.listPullRequests(in: $0) },
            createWorkspace: { try await service.createWorkspace(in: $0, request: $1) },
            importWorkspaces: { try await service.importWorkspaces(at: $0, into: $1) }
        )
    }
}
