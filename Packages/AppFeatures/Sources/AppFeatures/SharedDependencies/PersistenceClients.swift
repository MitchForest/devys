import Dependencies
import Foundation
import Workspace

public struct LayoutPersistenceClient: Sendable {
    public var loadDefaultLayout: @MainActor @Sendable () -> PanelLayout
    public var saveDefaultLayout: @MainActor @Sendable (PanelLayout) -> Void

    public init(
        loadDefaultLayout: @escaping @MainActor @Sendable () -> PanelLayout,
        saveDefaultLayout: @escaping @MainActor @Sendable (PanelLayout) -> Void
    ) {
        self.loadDefaultLayout = loadDefaultLayout
        self.saveDefaultLayout = saveDefaultLayout
    }
}

extension LayoutPersistenceClient: DependencyKey {
    public static let liveValue = Self(
        loadDefaultLayout: { PanelLayout.default },
        saveDefaultLayout: { _ in }
    )
}

extension LayoutPersistenceClient: TestDependencyKey {
    public static let testValue = Self(
        loadDefaultLayout: unimplemented(
            "\(Self.self).loadDefaultLayout",
            placeholder: PanelLayout.default
        ),
        saveDefaultLayout: unimplemented("\(Self.self).saveDefaultLayout")
    )
}

public extension DependencyValues {
    var layoutPersistenceClient: LayoutPersistenceClient {
        get { self[LayoutPersistenceClient.self] }
        set { self[LayoutPersistenceClient.self] = newValue }
    }
}

public extension LayoutPersistenceClient {
    static func live(service: LayoutPersistenceService) -> Self {
        Self(
            loadDefaultLayout: { service.loadDefaultLayout() },
            saveDefaultLayout: { service.saveDefaultLayout($0) }
        )
    }
}

public struct WindowRelaunchPersistenceClient: Sendable {
    public var load: @MainActor @Sendable () -> WindowRelaunchSnapshot?
    public var save: @MainActor @Sendable (WindowRelaunchSnapshot) throws -> Void
    public var clear: @MainActor @Sendable () throws -> Void

    public init(
        load: @escaping @MainActor @Sendable () -> WindowRelaunchSnapshot?,
        save: @escaping @MainActor @Sendable (WindowRelaunchSnapshot) throws -> Void,
        clear: @escaping @MainActor @Sendable () throws -> Void
    ) {
        self.load = load
        self.save = save
        self.clear = clear
    }
}

extension WindowRelaunchPersistenceClient: DependencyKey {
    public static let liveValue = Self(
        load: { nil },
        save: { _ in },
        clear: {}
    )
}

extension WindowRelaunchPersistenceClient: TestDependencyKey {
    public static let testValue = Self(
        load: unimplemented("\(Self.self).load", placeholder: nil),
        save: unimplemented("\(Self.self).save"),
        clear: unimplemented("\(Self.self).clear")
    )
}

public extension DependencyValues {
    var windowRelaunchPersistenceClient: WindowRelaunchPersistenceClient {
        get { self[WindowRelaunchPersistenceClient.self] }
        set { self[WindowRelaunchPersistenceClient.self] = newValue }
    }
}

public struct RepositorySettingsClient: Sendable {
    public var load: @MainActor @Sendable (URL?) -> RepositorySettings
    public var update: @MainActor @Sendable (RepositorySettings, URL) -> Void

    public init(
        load: @escaping @MainActor @Sendable (URL?) -> RepositorySettings,
        update: @escaping @MainActor @Sendable (RepositorySettings, URL) -> Void
    ) {
        self.load = load
        self.update = update
    }
}

extension RepositorySettingsClient: DependencyKey {
    public static let liveValue = Self(
        load: { _ in RepositorySettings() },
        update: { _, _ in }
    )
}

extension RepositorySettingsClient: TestDependencyKey {
    public static let testValue = Self(
        load: unimplemented("\(Self.self).load", placeholder: RepositorySettings()),
        update: unimplemented("\(Self.self).update")
    )
}

public extension DependencyValues {
    var repositorySettingsClient: RepositorySettingsClient {
        get { self[RepositorySettingsClient.self] }
        set { self[RepositorySettingsClient.self] = newValue }
    }
}

public extension RepositorySettingsClient {
    static func live(store: RepositorySettingsStore) -> Self {
        Self(
            load: { store.settings(for: $0) },
            update: { store.updateSettings($0, for: $1) }
        )
    }
}
