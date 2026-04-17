import ACPClientKit
import AppFeatures
import ComposableArchitecture
import Foundation
import Git
import Workspace

@MainActor
enum AppFeaturesBootstrap {
    static let navigatorCollapsedDefaultsKey = "com.devys.navigator.collapsed"

    static func makeStore(container: AppContainer) -> StoreOf<AppFeature> {
        let defaultLaunchOptions = makeDefaultLaunchOptions(container: container)
        let workspaceCatalogPersistenceClient = WorkspaceCatalogPersistenceClient.live()
        let windowRelaunchPersistenceStore = TerminalRelaunchPersistenceStore()
        let workflowPersistenceStore = WorkflowPersistenceStore()
        let notificationSettings = container.appSettings.notifications
        let initialWindowState = WindowFeature.State(
            workspaceStatesByID: Dictionary(
                uniqueKeysWithValues: workspaceCatalogPersistenceClient
                    .loadWorkspaceStates()
                    .map { ($0.worktreeId, $0) }
            ),
            isNavigatorCollapsed: UserDefaults.standard.bool(
                forKey: navigatorCollapsedDefaultsKey
            ),
            isTerminalActivityNotificationsEnabled: notificationSettings.terminalActivity,
            isAgentActivityNotificationsEnabled: notificationSettings.agentActivity
        )

        return withDependencies {
            $0.globalSettingsClient = .live(appSettings: container.appSettings)
            $0.recentRepositoriesClient = .live(service: container.recentRepositoriesService)
            $0.repositoryDiscoveryClient = .live(service: container.repositoryDiscoveryService)
            $0.layoutPersistenceClient = .live(service: container.layoutPersistenceService)
            $0.repositorySettingsClient = .live(store: container.repositorySettingsStore)
            $0.windowRelaunchPersistenceClient = .live(store: windowRelaunchPersistenceStore)
            $0.workspaceCreationClient = .live(service: container.workspaceCreationService)
            $0.workspaceCatalogPersistenceClient = workspaceCatalogPersistenceClient
            $0.workspaceCatalogRefreshClient = .live(
                gitWorktreeService: DefaultGitWorktreeService()
            )
            $0.workspaceOperationalClient = .live(
                controller: container.workspaceOperationalController
            )
            $0.workspaceAttentionIngressClient = .live()
            $0.workflowPersistenceClient = .live(store: workflowPersistenceStore)
            $0.workflowExecutionClient = .live(
                controller: container.workflowExecutionController
            )
            $0.agentLauncherClient = .live(
                launcher: container.agentAdapterLauncher,
                defaultLaunchOptions: defaultLaunchOptions
            )
        } operation: {
            Store(initialState: AppFeature.State(window: initialWindowState)) {
                AppFeature()
            }
        }
    }

    private static func makeDefaultLaunchOptions(
        container: AppContainer
    ) -> @MainActor @Sendable (URL?, URL?) -> ACPAdapterLaunchOptions {
        { configuredExecutableURL, currentDirectoryURL in
            container.defaultAgentAdapterLaunchOptions(
                configuredExecutableURL: configuredExecutableURL,
                currentDirectoryURL: currentDirectoryURL
            )
        }
    }
}

private extension WindowRelaunchPersistenceClient {
    @MainActor
    static func live(store: TerminalRelaunchPersistenceStore) -> Self {
        Self(
            load: { store.load() },
            save: { try store.save($0) },
            clear: { try store.clear() }
        )
    }
}

private extension WorkflowPersistenceClient {
    static func live(store: WorkflowPersistenceStore) -> Self {
        Self(
            loadWorkspace: { workspaceID, rootURL in
                try await store.loadWorkspace(workspaceID: workspaceID, rootURL: rootURL)
            },
            saveDefinition: { definition, rootURL in
                try await store.saveDefinition(definition, rootURL: rootURL)
            },
            deleteDefinition: { definitionID, rootURL in
                try await store.deleteDefinition(definitionID, rootURL: rootURL)
            },
            saveRun: { run, rootURL in
                try await store.saveRun(run, rootURL: rootURL)
            },
            deleteRun: { runID, rootURL in
                try await store.deleteRun(runID, rootURL: rootURL)
            },
            loadPlanSnapshot: { planFilePath, rootURL in
                try await store.loadPlanSnapshot(planFilePath: planFilePath, rootURL: rootURL)
            },
            appendFollowUpTicket: { request, rootURL in
                try await store.appendFollowUpTicket(request, rootURL: rootURL)
            }
        )
    }
}

private extension WorkflowExecutionClient {
    static func live(
        controller: WorkflowExecutionController
    ) -> Self {
        Self(
            updates: {
                controller.updates()
            },
            registerRuns: { runs in
                await controller.registerRuns(runs)
            },
            startNode: { request in
                try await controller.startNode(request)
            },
            stopRun: { runID in
                controller.stopRun(runID)
            }
        )
    }
}

private extension WorkspaceOperationalClient {
    static func live(
        controller: WorkspaceOperationalController
    ) -> Self {
        Self(
            updates: {
                controller.updates()
            },
            sync: { context, mode in
                controller.sync(context, mode: mode)
            },
            markTerminalRead: { workspaceID, terminalID in
                controller.markTerminalRead(terminalID, in: workspaceID)
            },
            requestMetadataRefresh: { worktreeIDs, repositoryID in
                controller.requestMetadataRefresh(
                    worktreeIDs: worktreeIDs,
                    repositoryID: repositoryID
                )
            },
            clearWorkspace: { workspaceID in
                controller.clearWorkspace(workspaceID)
            }
        )
    }
}

private extension WorkspaceAttentionIngressClient {
    static func live(
        notificationCenter: NotificationCenter = .default
    ) -> Self {
        Self {
            AsyncStream { continuation in
                let observer = notificationCenter.addObserver(
                    forName: .devysWorkspaceAttentionIngress,
                    object: nil,
                    queue: .main
                ) { notification in
                    guard let payload = try? WorkspaceAttentionIngress.decode(
                        userInfo: notification.userInfo
                    ) else {
                        return
                    }
                    continuation.yield(payload)
                }
                let removeObserver: @MainActor @Sendable () -> Void = {
                    notificationCenter.removeObserver(observer)
                }
                continuation.onTermination = { _ in
                    Task {
                        await removeObserver()
                    }
                }
            }
        }
    }
}
