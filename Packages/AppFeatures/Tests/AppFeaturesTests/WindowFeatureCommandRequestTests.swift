import ACPClientKit
import AppFeatures
import ComposableArchitecture
import Foundation
import Split
import Testing
import Workspace

@Suite("WindowFeature Command Request Tests")
struct WindowFeatureCommandRequestTests {
    @Test("Requesting shell actions emits explicit one-shot requests")
    @MainActor
    func commandRequests() async {
        let requestID = UUID(7)
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestOpenRepository) {
            $0.openRepositoryRequestID = requestID
        }

        await store.send(.setOpenRepositoryRequestID(nil)) {
            $0.openRepositoryRequestID = nil
        }

        await store.send(.requestEditorCommand(.saveAll)) {
            $0.editorCommandRequest = WindowFeature.EditorCommandRequest(
                command: .saveAll,
                id: requestID
            )
        }

        await store.send(.setEditorCommandRequest(nil)) {
            $0.editorCommandRequest = nil
        }

        let cleanTabID = TabID()
        let cleanPaneID = PaneID()
        let cleanContext = WindowFeature.WorkspaceTabCloseContext(
            tabID: cleanTabID,
            paneID: cleanPaneID,
            content: .settings,
            isDirtyEditor: false
        )

        await store.send(.requestWorkspaceTabClose(cleanContext)) {
            $0.workspaceTabCloseRequest = WindowFeature.WorkspaceTabCloseRequest(
                context: cleanContext,
                strategy: .closeImmediately,
                id: requestID
            )
        }

        await store.send(.setWorkspaceTabCloseRequest(nil)) {
            $0.workspaceTabCloseRequest = nil
        }

        await store.send(.requestWorkspaceCommand(.launchShell)) {
            $0.workspaceCommandRequest = WindowFeature.WorkspaceCommandRequest(
                command: .launchShell,
                id: requestID
            )
        }

        await store.send(.setWorkspaceCommandRequest(nil)) {
            $0.workspaceCommandRequest = nil
        }
    }

    @Test("Dirty editor tab close requests are resolved in the reducer before host confirmation")
    @MainActor
    func workspaceTabCloseRequest() async {
        let requestID = UUID(14)
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let tabID = TabID()
        let paneID = PaneID()
        let context = WindowFeature.WorkspaceTabCloseContext(
            tabID: tabID,
            paneID: paneID,
            content: .editor(
                workspaceID: workspaceID,
                url: URL(fileURLWithPath: "/tmp/devys-project/workspaces/feature/Sources/App.swift")
            ),
            isDirtyEditor: true
        )
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestWorkspaceTabClose(context)) {
            $0.workspaceTabCloseRequest = WindowFeature.WorkspaceTabCloseRequest(
                context: context,
                strategy: .confirmDirtyEditor(fileName: "App.swift"),
                id: requestID
            )
        }

        await store.send(.setWorkspaceTabCloseRequest(nil)) {
            $0.workspaceTabCloseRequest = nil
        }
    }

    @Test("Agent launch requests resolve the configured default harness in the reducer")
    @MainActor
    func agentSessionLaunchRequestUsesConfiguredDefaultHarness() async {
        let requestID = UUID(15)
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let intent = WindowFeature.AgentSessionLaunchIntent(
            workspaceID: workspaceID,
            initialAttachments: [.snippet(language: "swift", content: "print(\"hi\")")]
        )
        let expectedRequest = WindowFeature.AgentSessionLaunchRequest(
            workspaceID: workspaceID,
            kind: .codex,
            initialAttachments: intent.initialAttachments,
            preferredPaneID: nil,
            id: requestID
        )
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.globalSettingsClient.load = {
                var settings = GlobalSettings()
                settings.agent.defaultHarness = AgentSettings.Harness.codex.rawValue
                return settings
            }
        }

        await store.send(.requestAgentSessionLaunch(intent))

        await store.receive(.agentSessionLaunchResolved(.request(expectedRequest))) {
            $0.agentSessionLaunchRequest = expectedRequest
        }

        await store.send(.setAgentSessionLaunchRequest(nil)) {
            $0.agentSessionLaunchRequest = nil
        }
    }

    @Test("Agent launch requests present the picker when no default harness is configured")
    @MainActor
    func agentSessionLaunchRequestPresentsPicker() async {
        let requestID = UUID(16)
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let intent = WindowFeature.AgentSessionLaunchIntent(
            workspaceID: workspaceID,
            initialAttachments: [.file(url: URL(fileURLWithPath: "/tmp/devys-project/README.md"))]
        )
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.globalSettingsClient.load = {
                GlobalSettings()
            }
        }

        await store.send(.requestAgentSessionLaunch(intent))

        await store.receive(
            .agentSessionLaunchResolved(
                .presentation(
                    AgentLaunchPresentation(
                        workspaceID: workspaceID,
                        initialAttachments: intent.initialAttachments,
                        preferredPaneID: nil,
                        pendingSessionID: nil,
                        pendingTabID: nil
                    )
                )
            )
        ) {
            $0.agentLaunchPresentation = AgentLaunchPresentation(
                workspaceID: workspaceID,
                initialAttachments: intent.initialAttachments,
                preferredPaneID: nil,
                pendingSessionID: nil,
                pendingTabID: nil
            )
        }
    }

    @Test("Run profile requests are resolved in the reducer before the host executes them")
    @MainActor
    func runProfileLaunchRequest() async {
        let requestID = UUID(12)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let startupProfile = StartupProfile(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            displayName: "Default Run",
            steps: [
                StartupProfileStep(
                    displayName: "Web",
                    command: "npm run dev",
                    launchMode: .newTab
                )
            ]
        )
        let settings = RepositorySettings(
            startupProfiles: [startupProfile],
            defaultStartupProfileID: startupProfile.id
        )
        let expectedRequest = WindowFeature.RunProfileLaunchRequest(
            workspaceID: workspace.id,
            resolvedProfile: ResolvedStartupProfile(
                profile: startupProfile,
                steps: [
                    ResolvedStartupProfileStep(
                        id: startupProfile.steps[0].id,
                        displayName: "Web",
                        workingDirectory: workspace.workingDirectory,
                        command: "npm run dev",
                        environment: [:],
                        launchMode: .newTab
                    )
                ]
            ),
            id: requestID
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.repositorySettingsClient.load = { rootURL in
                #expect(rootURL == repository.rootURL)
                return settings
            }
        }

        await store.send(.requestWorkspaceCommand(.runWorkspaceProfile))

        await store.receive(.runProfileLaunchRequestResolved(.ready(expectedRequest))) {
            $0.runProfileLaunchRequest = expectedRequest
        }
    }

    @Test("Workspace transition requests are derived from reducer state")
    @MainActor
    func workspaceTransitionRequests() async {
        let requestID = UUID(9)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspace = Worktree(
            name: "main",
            detail: ".",
            workingDirectory: repository.rootURL,
            repositoryRootURL: repository.rootURL
        )
        let secondWorkspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [firstWorkspace, secondWorkspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: firstWorkspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestWorkspaceSelectionAtIndex(1)) {
            $0.workspaceTransitionRequest = WindowFeature.WorkspaceTransitionRequest(
                sourceRepositoryID: repository.id,
                sourceWorkspaceID: firstWorkspace.id,
                targetRepositoryID: repository.id,
                targetWorkspaceID: secondWorkspace.id,
                requiresRepositoryConfirmation: false,
                shouldPersistVisibleWorkspaceState: true,
                shouldResetHostWorkspaceState: false,
                catalogRefreshStrategy: .none,
                shouldScheduleDeferredRefresh: false,
                id: requestID
            )
        }

        await store.send(.setWorkspaceTransitionRequest(nil)) {
            $0.workspaceTransitionRequest = nil
        }

        await store.send(.requestAdjacentWorkspaceSelection(1)) {
            $0.workspaceTransitionRequest = WindowFeature.WorkspaceTransitionRequest(
                sourceRepositoryID: repository.id,
                sourceWorkspaceID: firstWorkspace.id,
                targetRepositoryID: repository.id,
                targetWorkspaceID: secondWorkspace.id,
                requiresRepositoryConfirmation: false,
                shouldPersistVisibleWorkspaceState: true,
                shouldResetHostWorkspaceState: false,
                catalogRefreshStrategy: .none,
                shouldScheduleDeferredRefresh: false,
                id: requestID
            )
        }

        await store.send(.setWorkspaceTransitionRequest(nil)) {
            $0.workspaceTransitionRequest = nil
        }
    }

    @Test("Repository transitions request host confirmation and retry refresh when needed")
    @MainActor
    func repositoryTransitionRequests() async {
        let requestID = UUID(10)
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let visibleWorkspace = Worktree(
            name: "main",
            detail: ".",
            workingDirectory: firstRepository.rootURL,
            repositoryRootURL: firstRepository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository, secondRepository],
                worktreesByRepository: [firstRepository.id: [visibleWorkspace]],
                selectedRepositoryID: firstRepository.id,
                selectedWorkspaceID: visibleWorkspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestRepositorySelection(secondRepository.id)) {
            $0.workspaceTransitionRequest = WindowFeature.WorkspaceTransitionRequest(
                sourceRepositoryID: firstRepository.id,
                sourceWorkspaceID: visibleWorkspace.id,
                targetRepositoryID: secondRepository.id,
                targetWorkspaceID: nil,
                requiresRepositoryConfirmation: true,
                shouldPersistVisibleWorkspaceState: true,
                shouldResetHostWorkspaceState: true,
                catalogRefreshStrategy: .retryIfSelectionMissing,
                shouldScheduleDeferredRefresh: false,
                id: requestID
            )
        }
    }

    @Test("Workspace discard requests are explicit one-shot host requests")
    @MainActor
    func workspaceDiscardRequest() async {
        let requestID = UUID(13)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestWorkspaceDiscard(workspaceID: workspaceID, repositoryID: repository.id)) {
            $0.workspaceDiscardRequest = WindowFeature.WorkspaceDiscardRequest(
                workspaceID: workspaceID,
                repositoryID: repository.id,
                id: requestID
            )
        }

        await store.send(.setWorkspaceDiscardRequest(nil)) {
            $0.workspaceDiscardRequest = nil
        }
    }

    @Test("Focus agent and reveal requests resolve from selected workspace state")
    @MainActor
    func workspaceScopedRequests() async {
        let requestID = UUID(11)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let sessionID = AgentSessionID(rawValue: "session-1")
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestFocusAgentSession(sessionID)) {
            $0.focusAgentSessionRequest = WindowFeature.FocusAgentSessionRequest(
                workspaceID: workspace.id,
                sessionID: sessionID,
                id: requestID
            )
        }

        await store.send(.setFocusAgentSessionRequest(nil)) {
            $0.focusAgentSessionRequest = nil
        }

        await store.send(.revealCurrentWorkspaceInNavigator) {
            $0.navigatorRevealRequest = WindowFeature.NavigatorRevealRequest(
                workspaceID: workspace.id,
                token: requestID
            )
        }
    }

    @Test("Window relaunch restore requests are resolved in the reducer before host execution")
    @MainActor
    func windowRelaunchRestoreRequest() async {
        let requestID = UUID(21)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let snapshot = WindowRelaunchSnapshot(
            repositoryRootURLs: [repository.rootURL],
            selectedRepositoryID: repository.id,
            selectedWorkspaceID: workspace.id,
            hostedSessions: [],
            workspaceStates: []
        )
        let expectedRequest = WindowFeature.WindowRelaunchRestoreRequest(
            snapshot: snapshot,
            settings: RelaunchSettingsSnapshot(
                restoreRepositoriesOnLaunch: true,
                restoreSelectedWorkspace: true,
                restoreWorkspaceLayoutAndTabs: true,
                restoreTerminalSessions: true,
                restoreAgentSessions: true
            ),
            id: requestID
        )
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
            $0.globalSettingsClient.load = {
                var settings = GlobalSettings()
                settings.restore.restoreRepositoriesOnLaunch = true
                settings.restore.restoreSelectedWorkspace = true
                settings.restore.restoreWorkspaceLayoutAndTabs = true
                settings.restore.restoreTerminalSessions = true
                settings.restore.restoreAgentSessions = true
                return settings
            }
            $0.windowRelaunchPersistenceClient.load = { snapshot }
        }

        await store.send(.requestWindowRelaunchRestore(force: false))

        await store.receive(
            .windowRelaunchRestoreLoaded(
                .success(snapshot),
                settings: expectedRequest.settings,
                force: false
            )
        ) {
            $0.windowRelaunchRestoreRequest = expectedRequest
        }

        await store.send(.setWindowRelaunchRestoreRequest(nil)) {
            $0.windowRelaunchRestoreRequest = nil
        }
    }

    @Test("Persisting the window relaunch snapshot is planned from reducer-owned shell state")
    @MainActor
    func persistWindowRelaunchSnapshot() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let paneID = PaneID()
        let terminalTabID = TabID()
        let agentTabID = TabID()
        let editorTabID = TabID()
        let hostedSession = HostedTerminalSessionRecord(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            workspaceID: workspace.id,
            workingDirectory: workspace.workingDirectory,
            launchCommand: "npm run dev",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let snapshotBox = SnapshotBox()
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                hostedWorkspaceContentByID: [
                    workspace.id: HostedWorkspaceContentState(
                        agentSessions: [
                            HostedAgentSessionSummary(
                                sessionID: AgentSessionID(rawValue: "agent-1"),
                                kind: .codex,
                                title: "Codex",
                                icon: "chevron.left.forwardslash.chevron.right",
                                subtitle: "Connected",
                                isBusy: false,
                                isRestorable: true,
                                createdAt: Date(timeIntervalSince1970: 1),
                                lastActivityAt: Date(timeIntervalSince1970: 2)
                            )
                        ]
                    )
                ],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id,
                workspaceShells: [
                    workspace.id: WindowFeature.WorkspaceShell(
                        activeSidebar: .agents,
                        tabContents: [
                            terminalTabID: .terminal(workspaceID: workspace.id, id: hostedSession.id),
                            agentTabID: .agentSession(
                                workspaceID: workspace.id,
                                sessionID: AgentSessionID(rawValue: "agent-1")
                            ),
                            editorTabID: .editor(
                                workspaceID: workspace.id,
                                url: workspace.workingDirectory.appendingPathComponent("App.swift")
                            )
                        ],
                        focusedPaneID: paneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .pane(
                                WindowFeature.WorkspacePaneLayout(
                                    id: paneID,
                                    tabIDs: [terminalTabID, agentTabID, editorTabID],
                                    selectedTabID: editorTabID
                                )
                            )
                        )
                    )
                ]
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.globalSettingsClient.load = {
                var settings = GlobalSettings()
                settings.restore.restoreSelectedWorkspace = true
                settings.restore.restoreWorkspaceLayoutAndTabs = true
                settings.restore.restoreTerminalSessions = true
                settings.restore.restoreAgentSessions = true
                return settings
            }
            $0.windowRelaunchPersistenceClient.save = { snapshot in
                snapshotBox.set(snapshot)
            }
            $0.windowRelaunchPersistenceClient.clear = {}
        }

        await store.send(WindowFeature.Action.persistWindowRelaunchSnapshot([hostedSession]))

        let savedSnapshot = snapshotBox.value
        #expect(savedSnapshot?.repositoryRootURLs == [repository.rootURL])
        #expect(savedSnapshot?.selectedRepositoryID == repository.id)
        #expect(savedSnapshot?.selectedWorkspaceID == workspace.id)
        #expect(savedSnapshot?.workspaceStates.first?.sidebarMode == .agents)
        #expect(savedSnapshot?.workspaceStates.first?.persistedTabs.count == 3)
    }

    @Test("Applying a window relaunch restore rebuilds reducer-owned selection and shells")
    @MainActor
    func applyWindowRelaunchRestore() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let snapshot = WindowRelaunchSnapshot(
            repositoryRootURLs: [repository.rootURL],
            selectedRepositoryID: repository.id,
            selectedWorkspaceID: workspace.id,
            hostedSessions: [],
            workspaceStates: [
                PersistedWorkspaceLayoutState(
                    workspaceID: workspace.id,
                    sidebarMode: .agents,
                    tree: .pane(
                        selectedTabIndex: 1,
                        tabs: [
                            .editor(fileURL: workspace.workingDirectory.appendingPathComponent("App.swift")),
                            .agent(
                                PersistedAgentSessionRecord(
                                    sessionID: "agent-1",
                                    kind: .codex,
                                    title: "Codex",
                                    subtitle: "Connected"
                                )
                            )
                        ]
                    )
                )
            ]
        )
        let request = WindowFeature.WindowRelaunchRestoreRequest(
            snapshot: snapshot,
            settings: RelaunchSettingsSnapshot(
                restoreRepositoriesOnLaunch: true,
                restoreSelectedWorkspace: true,
                restoreWorkspaceLayoutAndTabs: true,
                restoreTerminalSessions: true,
                restoreAgentSessions: true
            )
        )
        var state = WindowFeature.State(
            repositories: [repository],
            worktreesByRepository: [repository.id: [workspace]]
        )
        let reducer = WindowFeature()

        _ = reducer.reduce(into: &state, action: .applyWindowRelaunchRestore(request))

        #expect(state.selectedRepositoryID == repository.id)
        #expect(state.selectedWorkspaceID == workspace.id)
        #expect(state.activeSidebar == .agents)
        #expect(state.workspaceShells[workspace.id]?.activeSidebar == .agents)
        #expect(state.workspaceShells[workspace.id]?.tabContents.count == 2)
        #expect(state.workspaceShells[workspace.id]?.layout != nil)
    }
}

@MainActor
private final class SnapshotBox {
    private(set) var value: WindowRelaunchSnapshot?

    func set(_ snapshot: WindowRelaunchSnapshot) {
        value = snapshot
    }
}
