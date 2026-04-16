import ACPClientKit
import Dependencies
import Foundation

public struct AgentLauncherClient: Sendable {
    public var defaultLaunchOptions: @MainActor @Sendable (URL?, URL?) -> ACPAdapterLaunchOptions
    public var resolve: @Sendable (ACPAgentDescriptor, ACPAdapterLaunchOptions) throws -> ACPResolvedAdapter
    public var launch: @Sendable (ACPAgentDescriptor, ACPAdapterLaunchOptions) async throws -> ACPLaunchedAdapter

    public init(
        defaultLaunchOptions: @escaping @MainActor @Sendable (URL?, URL?) -> ACPAdapterLaunchOptions,
        resolve: @escaping @Sendable (ACPAgentDescriptor, ACPAdapterLaunchOptions) throws -> ACPResolvedAdapter,
        launch: @escaping @Sendable (ACPAgentDescriptor, ACPAdapterLaunchOptions) async throws -> ACPLaunchedAdapter
    ) {
        self.defaultLaunchOptions = defaultLaunchOptions
        self.resolve = resolve
        self.launch = launch
    }
}

extension AgentLauncherClient: DependencyKey {
    public static let liveValue = Self(
        defaultLaunchOptions: { _, currentDirectoryURL in
            ACPAdapterLaunchOptions(currentDirectoryURL: currentDirectoryURL)
        },
        resolve: { descriptor, options in
            try ACPAdapterLauncher().resolve(descriptor: descriptor, options: options)
        },
        launch: { descriptor, options in
            try await ACPAdapterLauncher().launch(descriptor: descriptor, options: options)
        }
    )
}

extension AgentLauncherClient: TestDependencyKey {
    public static let testValue = Self(
        defaultLaunchOptions: unimplemented(
            "\(Self.self).defaultLaunchOptions",
            placeholder: ACPAdapterLaunchOptions()
        ),
        resolve: unimplemented("\(Self.self).resolve"),
        launch: unimplemented("\(Self.self).launch")
    )
}

public extension DependencyValues {
    var agentLauncherClient: AgentLauncherClient {
        get { self[AgentLauncherClient.self] }
        set { self[AgentLauncherClient.self] = newValue }
    }
}

public extension AgentLauncherClient {
    static func live(
        launcher: ACPAdapterLauncher,
        defaultLaunchOptions: @escaping @MainActor @Sendable (URL?, URL?) -> ACPAdapterLaunchOptions
    ) -> Self {
        Self(
            defaultLaunchOptions: defaultLaunchOptions,
            resolve: { descriptor, options in
                try launcher.resolve(descriptor: descriptor, options: options)
            },
            launch: { descriptor, options in
                try await launcher.launch(descriptor: descriptor, options: options)
            }
        )
    }
}
