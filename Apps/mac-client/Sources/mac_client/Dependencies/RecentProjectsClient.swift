import ComposableArchitecture
import Foundation

struct RecentProjectsClient: Sendable {
    var load: @Sendable () async -> [URL]
    var record: @Sendable (URL) async -> Void

    init(
        load: @escaping @Sendable () async -> [URL],
        record: @escaping @Sendable (URL) async -> Void
    ) {
        self.load = load
        self.record = record
    }
}

private enum RecentProjectsClientKey: DependencyKey {
    static let liveValue = RecentProjectsClient(
        load: { [] },
        record: { _ in }
    )
}

extension DependencyValues {
    var recentProjectsClient: RecentProjectsClient {
        get { self[RecentProjectsClientKey.self] }
        set { self[RecentProjectsClientKey.self] = newValue }
    }
}
