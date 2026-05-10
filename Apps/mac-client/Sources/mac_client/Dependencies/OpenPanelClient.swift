import ComposableArchitecture
import Foundation

struct OpenPanelClient: Sendable {
    var chooseProjectDirectory: @Sendable () async -> URL?

    init(chooseProjectDirectory: @escaping @Sendable () async -> URL?) {
        self.chooseProjectDirectory = chooseProjectDirectory
    }
}

private enum OpenPanelClientKey: DependencyKey {
    static let liveValue = OpenPanelClient { nil }
}

extension DependencyValues {
    var openPanelClient: OpenPanelClient {
        get { self[OpenPanelClientKey.self] }
        set { self[OpenPanelClientKey.self] = newValue }
    }
}
