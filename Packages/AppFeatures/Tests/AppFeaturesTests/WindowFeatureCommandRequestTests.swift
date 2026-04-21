import ACPClientKit
import ComposableArchitecture
import Foundation
import Git
import Split
import Testing
import Workspace
@testable import AppFeatures

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

        await store.send(.requestAddRepository) {
            $0.addRepositoryPresentation = AddRepositoryPresentation(id: requestID)
        }

        await store.send(.setAddRepositoryPresentation(nil)) {
            $0.addRepositoryPresentation = nil
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

    @Test("Chat launch requests resolve the configured default harness in the reducer")
    @MainActor
    func chatSessionLaunchRequestUsesConfiguredDefaultHarness() async {
        let requestID = UUID(15)
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let intent = WindowFeature.ChatSessionLaunchIntent(
            workspaceID: workspaceID,
            initialAttachments: [.snippet(language: "swift", content: "print(\"hi\")")]
        )
        let expectedRequest = WindowFeature.ChatSessionLaunchRequest(
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
                settings.chat.defaultHarness = ChatSettings.Harness.codex.rawValue
                return settings
            }
        }

        await store.send(.requestChatSessionLaunch(intent))

        await store.receive(.chatSessionLaunchResolved(.request(expectedRequest))) {
            $0.chatSessionLaunchRequest = expectedRequest
        }

        await store.send(.setChatSessionLaunchRequest(nil)) {
            $0.chatSessionLaunchRequest = nil
        }
    }

    @Test("Chat launch requests present the picker when no default harness is configured")
    @MainActor
    func chatSessionLaunchRequestPresentsPicker() async {
        let requestID = UUID(16)
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let intent = WindowFeature.ChatSessionLaunchIntent(
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

        await store.send(.requestChatSessionLaunch(intent))

        await store.receive(
            .chatSessionLaunchResolved(
                .presentation(
                    ChatLaunchPresentation(
                        workspaceID: workspaceID,
                        initialAttachments: intent.initialAttachments,
                        preferredPaneID: nil,
                        pendingSessionID: nil,
                        pendingTabID: nil
                    )
                )
            )
        ) {
            $0.chatLaunchPresentation = ChatLaunchPresentation(
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

    @Test("Review command presents the reducer-owned target picker instead of a host command request")
    @MainActor
    func reviewCommandPresentsTargetPicker() async {
        let requestID = UUID(17)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
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
        }

        await store.send(.requestWorkspaceCommand(.runReview)) {
            $0.reviewEntryPresentation = WindowFeature.ReviewEntryPresentation(
                id: requestID,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                workspaceName: workspace.name,
                branchName: workspace.name
            )
            $0.workspaceCommandRequest = nil
        }

        await store.send(.setReviewEntryPresentation(nil)) {
            $0.reviewEntryPresentation = nil
        }
    }

    @Test("Review command exposes pull-request target when workspace PR metadata exists")
    @MainActor
    func reviewCommandIncludesPullRequestTarget() async {
        let requestID = UUID(18)
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature/login-review",
            detail: "feature/login-review",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-login-review"),
            repositoryRootURL: repository.rootURL
        )
        let pullRequest = PullRequest(
            id: 42,
            number: 42,
            title: "Harden login review flow",
            body: nil,
            state: .open,
            author: "devys",
            headBranch: workspace.name,
            baseBranch: "main",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            isDraft: false,
            checksStatus: .passing,
            reviewDecision: .reviewRequired,
            additions: 10,
            deletions: 2,
            changedFiles: 3
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id,
                operational: {
                    var operational = WorkspaceOperationalState()
                    operational.metadataEntriesByWorkspaceID[workspace.id] = WorktreeInfoEntry(
                        branchName: workspace.name,
                        pullRequest: pullRequest
                    )
                    return operational
                }()
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestWorkspaceCommand(.runReview)) {
            $0.reviewEntryPresentation = WindowFeature.ReviewEntryPresentation(
                id: requestID,
                workspaceID: workspace.id,
                repositoryRootURL: repository.rootURL,
                workspaceName: workspace.name,
                branchName: workspace.name,
                pullRequestNumber: 42,
                pullRequestTitle: "Harden login review flow",
                availableTargets: ReviewTargetKind.manualEntryTargets + [.pullRequest]
            )
            $0.workspaceCommandRequest = nil
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

    @Test("Focus chat and reveal requests resolve from selected workspace state")
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
        let sessionID = ChatSessionID(rawValue: "session-1")
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

        await store.send(.requestFocusChatSession(sessionID)) {
            $0.focusChatSessionRequest = WindowFeature.FocusChatSessionRequest(
                workspaceID: workspace.id,
                sessionID: sessionID,
                id: requestID
            )
        }

        await store.send(.setFocusChatSessionRequest(nil)) {
            $0.focusChatSessionRequest = nil
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
                restoreChatSessions: true
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
                settings.restore.restoreChatSessions = true
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
        let browserTabID = TabID()
        let agentTabID = TabID()
        let editorTabID = TabID()
        let workflowDefinitionTabID = TabID()
        let workflowRunTabID = TabID()
        let reviewRunTabID = TabID()
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
                        browserSessions: [
                            HostedBrowserSessionSummary(
                                sessionID: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                                url: URL(string: "http://localhost:3000/dashboard")!,
                                title: "Local App",
                                icon: "globe"
                            )
                        ],
                        chatSessions: [
                            HostedChatSessionSummary(
                                sessionID: ChatSessionID(rawValue: "agent-1"),
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
                            browserTabID: .browser(
                                workspaceID: workspace.id,
                                id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                                initialURL: URL(string: "http://localhost:3000")!
                            ),
                            agentTabID: .chatSession(
                                workspaceID: workspace.id,
                                sessionID: ChatSessionID(rawValue: "agent-1")
                            ),
                            workflowDefinitionTabID: .workflowDefinition(
                                workspaceID: workspace.id,
                                definitionID: "delivery"
                            ),
                            workflowRunTabID: .workflowRun(
                                workspaceID: workspace.id,
                                runID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
                            ),
                            reviewRunTabID: .reviewRun(
                                workspaceID: workspace.id,
                                runID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
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
                                tabIDs: [
                                    terminalTabID,
                                    browserTabID,
                                    agentTabID,
                                    workflowDefinitionTabID,
                                    workflowRunTabID,
                                    reviewRunTabID,
                                    editorTabID
                                ],
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
                settings.restore.restoreChatSessions = true
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
        #expect(savedSnapshot?.workspaceStates.first?.persistedTabs.count == 7)
        #expect(
            savedSnapshot?.workspaceStates.first?.persistedTabs.contains(
                .browser(
                    id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                    url: URL(string: "http://localhost:3000/dashboard")!
                )
            ) == true
        )
        #expect(
            savedSnapshot?.workspaceStates.first?.persistedTabs.contains(
                .reviewRun(runID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
            ) == true
        )
    }

    @Test("Persisting the window relaunch snapshot skips handled review tabs")
    @MainActor
    func persistWindowRelaunchSnapshotSkipsHandledReviewTabs() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let paneID = PaneID()
        let editorTabID = TabID()
        let reviewRunTabID = TabID()
        let reviewRunID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let issueID = UUID(uuidString: "aaaaaaaa-2222-3333-4444-555555555555")!
        let snapshotBox = SnapshotBox()

        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                reviewWorkspacesByID: [
                    workspace.id: WindowFeature.ReviewWorkspaceState(
                        runs: [
                            ReviewRun(
                                id: reviewRunID,
                                target: ReviewTarget(
                                    id: "\(workspace.id):stagedChanges",
                                    kind: .stagedChanges,
                                    workspaceID: workspace.id,
                                    repositoryRootURL: repository.rootURL,
                                    title: "Staged Changes",
                                    branchName: workspace.name
                                ),
                                trigger: ReviewTrigger(source: .manual),
                                profile: ReviewProfile(),
                                status: .completed,
                                issueCounts: ReviewIssueCounts(total: 1, dismissed: 1, critical: 1),
                                issueIDs: [issueID]
                            )
                        ],
                        issuesByRunID: [
                            reviewRunID: [
                                ReviewIssue(
                                    id: issueID,
                                    runID: reviewRunID,
                                    severity: .critical,
                                    confidence: .high,
                                    title: "Handled issue",
                                    summary: "Already handled.",
                                    rationale: "No further action needed.",
                                    dedupeKey: "handled-issue",
                                    status: .dismissed
                                )
                            ]
                        ]
                    )
                ],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id,
                workspaceShells: [
                    workspace.id: WindowFeature.WorkspaceShell(
                        tabContents: [
                            editorTabID: .editor(
                                workspaceID: workspace.id,
                                url: workspace.workingDirectory.appendingPathComponent("App.swift")
                            ),
                            reviewRunTabID: .reviewRun(
                                workspaceID: workspace.id,
                                runID: reviewRunID
                            )
                        ],
                        focusedPaneID: paneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .pane(
                                WindowFeature.WorkspacePaneLayout(
                                    id: paneID,
                                    tabIDs: [editorTabID, reviewRunTabID],
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
                return settings
            }
            $0.windowRelaunchPersistenceClient.save = { snapshot in
                snapshotBox.set(snapshot)
            }
            $0.windowRelaunchPersistenceClient.clear = {}
        }

        await store.send(.persistWindowRelaunchSnapshot([]))

        let savedSnapshot = snapshotBox.value
        #expect(
            savedSnapshot?.workspaceStates.first?.persistedTabs.contains(
                .editor(fileURL: workspace.workingDirectory.appendingPathComponent("App.swift"))
            ) == true
        )
        #expect(
            savedSnapshot?.workspaceStates.first?.persistedTabs.contains(
                .reviewRun(runID: reviewRunID)
            ) == false
        )
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
                            .browser(
                                id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                                url: URL(string: "http://localhost:3000/dashboard")!
                            ),
                            .chat(
                                PersistedChatSessionRecord(
                                    sessionID: "agent-1",
                                    kind: .codex,
                                    title: "Codex",
                                    subtitle: "Connected"
                                )
                            ),
                            .workflowDefinition(definitionID: "delivery"),
                            .workflowRun(runID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!),
                            .reviewRun(runID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
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
                restoreChatSessions: true
            )
        )
        var state = WindowFeature.State(
            repositories: [repository],
            worktreesByRepository: [repository.id: [workspace]]
        )
        state.applyWindowRelaunchRestore(request)

        #expect(state.selectedRepositoryID == repository.id)
        #expect(state.selectedWorkspaceID == workspace.id)
        #expect(state.activeSidebar == .agents)
        #expect(state.workspaceShells[workspace.id]?.activeSidebar == .agents)
        #expect(state.workspaceShells[workspace.id]?.tabContents.count == 6)
        #expect(state.workspaceShells[workspace.id]?.layout != nil)
        #expect(
            state.workspaceShells[workspace.id]?.tabContents.values.contains(
                .browser(
                    workspaceID: workspace.id,
                    id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!,
                    initialURL: URL(string: "http://localhost:3000/dashboard")!
                )
            ) == true
        )
        #expect(
            state.workspaceShells[workspace.id]?.tabContents.values.contains(
                .workflowDefinition(workspaceID: workspace.id, definitionID: "delivery")
            ) == true
        )
        #expect(
            state.workspaceShells[workspace.id]?.tabContents.values.contains(
                .workflowRun(
                    workspaceID: workspace.id,
                    runID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
                )
            ) == true
        )
        #expect(
            state.workspaceShells[workspace.id]?.tabContents.values.contains(
                .reviewRun(
                    workspaceID: workspace.id,
                    runID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
                )
            ) == true
        )
    }

    @Test("Applying a window relaunch restore reloads review and workflow data for the restored workspace")
    @MainActor
    func applyWindowRelaunchRestoreLoadsSelectedWorkspaceData() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let request = WindowFeature.WindowRelaunchRestoreRequest(
            snapshot: WindowRelaunchSnapshot(
                repositoryRootURLs: [repository.rootURL],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspace.id,
                hostedSessions: [],
                workspaceStates: []
            ),
            settings: RelaunchSettingsSnapshot(
                restoreRepositoriesOnLaunch: true,
                restoreSelectedWorkspace: true,
                restoreWorkspaceLayoutAndTabs: true,
                restoreTerminalSessions: true,
                restoreChatSessions: true
            )
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]]
            )
        ) {
            WindowFeature()
        }
        store.exhaustivity = .off

        await store.send(.applyWindowRelaunchRestore(request))
        await store.receive(.reviewWorkspaceLoadRequested(workspace.id)) {
            $0.reviewWorkspacesByID[workspace.id] = WindowFeature.ReviewWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(.workflowWorkspaceLoadRequested(workspace.id)) {
            $0.workflowWorkspacesByID[workspace.id] = WindowFeature.WorkflowWorkspaceState(
                isLoading: true
            )
        }
    }
}

@MainActor
private final class SnapshotBox {
    private(set) var value: WindowRelaunchSnapshot?

    func set(_ snapshot: WindowRelaunchSnapshot) {
        value = snapshot
    }
}
