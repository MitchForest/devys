import Dependencies
import Foundation
import Workspace

public struct GlobalSettingsClient: Sendable {
    public var load: @MainActor @Sendable () -> GlobalSettings
    public var save: @MainActor @Sendable (GlobalSettings) -> Void

    public init(
        load: @escaping @MainActor @Sendable () -> GlobalSettings,
        save: @escaping @MainActor @Sendable (GlobalSettings) -> Void
    ) {
        self.load = load
        self.save = save
    }
}

extension GlobalSettingsClient: DependencyKey {
    public static let liveValue = Self(
        load: { GlobalSettings() },
        save: { _ in }
    )
}

extension GlobalSettingsClient: TestDependencyKey {
    public static let testValue = Self(
        load: unimplemented("\(Self.self).load", placeholder: GlobalSettings()),
        save: unimplemented("\(Self.self).save")
    )
}

public extension DependencyValues {
    var globalSettingsClient: GlobalSettingsClient {
        get { self[GlobalSettingsClient.self] }
        set { self[GlobalSettingsClient.self] = newValue }
    }
}

public extension GlobalSettingsClient {
    static func live(appSettings: AppSettings) -> Self {
        Self(
            load: {
                GlobalSettings(
                    shell: appSettings.shell,
                    explorer: appSettings.explorer,
                    appearance: appSettings.appearance,
                    chat: appSettings.chat,
                    notifications: appSettings.notifications,
                    restore: appSettings.restore,
                    shortcuts: appSettings.shortcuts
                )
            },
            save: { settings in
                appSettings.shell = settings.shell
                appSettings.explorer = settings.explorer
                appSettings.appearance = settings.appearance
                appSettings.chat = settings.chat
                appSettings.notifications = settings.notifications
                appSettings.restore = settings.restore
                appSettings.shortcuts = settings.shortcuts
            }
        )
    }
}
