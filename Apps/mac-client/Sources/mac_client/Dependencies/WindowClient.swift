import ComposableArchitecture
import Foundation

enum WindowOpenDisposition: Equatable, Sendable {
    case newWindow
    case currentWindowGroup
}

enum WindowTabKind: Equatable, Sendable {
    case terminal
    case file(URL)
    case reader(URL)
    case diff(String)
    case browser(URL)
}

struct WindowOpenRequest: Equatable, Sendable {
    var disposition: WindowOpenDisposition
    var tabKind: WindowTabKind
    var projectRootURL: URL?

    init(
        disposition: WindowOpenDisposition,
        tabKind: WindowTabKind,
        projectRootURL: URL? = nil
    ) {
        self.disposition = disposition
        self.tabKind = tabKind
        self.projectRootURL = projectRootURL?.standardizedFileURL
    }
}

struct WindowClient: Sendable {
    var open: @Sendable (WindowOpenRequest) async -> Void

    init(open: @escaping @Sendable (WindowOpenRequest) async -> Void) {
        self.open = open
    }
}

private enum WindowClientKey: DependencyKey {
    static let liveValue = WindowClient { _ in }
}

extension DependencyValues {
    var windowClient: WindowClient {
        get { self[WindowClientKey.self] }
        set { self[WindowClientKey.self] = newValue }
    }
}
