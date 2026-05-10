import ComposableArchitecture
import Foundation

struct ProjectRootResolverClient: Sendable {
    var resolveCandidateProjectRoot: @Sendable (URL) async -> URL?

    init(resolveCandidateProjectRoot: @escaping @Sendable (URL) async -> URL?) {
        self.resolveCandidateProjectRoot = resolveCandidateProjectRoot
    }
}

private enum ProjectRootResolverClientKey: DependencyKey {
    static let liveValue = ProjectRootResolverClient { _ in nil }
}

extension DependencyValues {
    var projectRootResolverClient: ProjectRootResolverClient {
        get { self[ProjectRootResolverClientKey.self] }
        set { self[ProjectRootResolverClientKey.self] = newValue }
    }
}
