import ComposableArchitecture
import Diff
import Foundation

struct DiffModePersistenceClient: Sendable {
    var loadMode: @Sendable () -> DiffViewMode
    var saveMode: @Sendable (DiffViewMode) -> Void

    init(
        loadMode: @escaping @Sendable () -> DiffViewMode,
        saveMode: @escaping @Sendable (DiffViewMode) -> Void
    ) {
        self.loadMode = loadMode
        self.saveMode = saveMode
    }
}

private enum DiffModePersistenceClientKey: DependencyKey {
    static let liveValue = DiffModePersistenceClient(
        loadMode: {
            guard let rawValue = UserDefaults.standard.string(forKey: diffModeDefaultsKey),
                  let mode = DiffViewMode(rawValue: rawValue) else {
                return .unified
            }
            return mode
        },
        saveMode: { mode in
            UserDefaults.standard.set(mode.rawValue, forKey: diffModeDefaultsKey)
        }
    )
}

extension DependencyValues {
    var diffModePersistenceClient: DiffModePersistenceClient {
        get { self[DiffModePersistenceClientKey.self] }
        set { self[DiffModePersistenceClientKey.self] = newValue }
    }
}

private let diffModeDefaultsKey = "com.devys.terminal.diff-mode"
