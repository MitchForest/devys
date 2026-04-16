import AppFeatures
import ComposableArchitecture
import Foundation
import Split
import Testing
import Workspace

@Suite("WindowFeature Tests")
struct WindowFeatureTests {
    @Test("Opening a repository imports it and selects it")
    @MainActor
    func openRepositorySuccess() async {
        let repositoryURL = URL(fileURLWithPath: "/tmp/devys-project")
        let resolvedRepository = Repository(rootURL: repositoryURL, sourceControl: .git)

        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.repositoryDiscoveryClient.resolveRepository = { _ in resolvedRepository }
            $0.recentRepositoriesClient.add = { _ in }
        }

        await store.send(.openRepository(repositoryURL))
        await store.receive(.openRepositoryResponse(.success(resolvedRepository))) {
            $0.repositories = [resolvedRepository]
            $0.selectedRepositoryID = resolvedRepository.id
        }
    }

    @Test("Repository discovery failures surface a readable error")
    @MainActor
    func openRepositoryFailure() async {
        struct Failure: LocalizedError, Equatable {
            var errorDescription: String? { "Repository lookup failed." }
        }

        let repositoryURL = URL(fileURLWithPath: "/tmp/devys-project")
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.repositoryDiscoveryClient.resolveRepository = { _ in throw Failure() }
        }

        await store.send(.openRepository(repositoryURL))
        await store.receive(.openRepositoryResponse(.failure(Failure()))) {
            $0.lastErrorMessage = "Repository lookup failed."
        }
    }

    @Test("Restoring selection preserves repository and workspace when valid")
    @MainActor
    func restoreSelection() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let store = TestStore(
            initialState: WindowFeature.State(repositories: [firstRepository, secondRepository])
        ) {
            WindowFeature()
        }

        await store.send(
            .restoreSelection(repositoryID: firstRepository.id, workspaceID: workspaceID)
        ) {
            $0.selectedRepositoryID = firstRepository.id
            $0.selectedWorkspaceID = workspaceID
        }
    }

    @Test("Replacing the catalog snapshot normalizes stale selection")
    @MainActor
    func setRepositoryCatalogSnapshotNormalizesSelection() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository, secondRepository],
                selectedRepositoryID: firstRepository.id,
                selectedWorkspaceID: "/tmp/devys-project/workspaces/main"
            )
        ) {
            WindowFeature()
        }

        await store.send(
            .setRepositoryCatalogSnapshot(
                WindowFeature.RepositoryCatalogSnapshot(repositories: [secondRepository])
            )
        ) {
            $0.repositories = [secondRepository]
            $0.selectedRepositoryID = secondRepository.id
            $0.selectedWorkspaceID = nil
        }
    }

    @Test("Showing a sidebar makes it active and visible")
    @MainActor
    func showSidebar() async {
        let store = TestStore(
            initialState: WindowFeature.State(
                activeSidebar: .files,
                isSidebarVisible: false
            )
        ) {
            WindowFeature()
        }

        await store.send(.showSidebar(.agents)) {
            $0.activeSidebar = .agents
            $0.isSidebarVisible = true
        }
    }

    @Test("Opening search presents a fresh search surface")
    @MainActor
    func openSearch() async {
        let searchID = UUID(1)
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(searchID)
        }

        await store.send(.openSearch(.commands, initialQuery: "ports")) {
            $0.searchPresentation = WindowFeature.SearchPresentation(
                mode: .commands,
                initialQuery: "ports",
                id: searchID
            )
        }
    }

    @Test("Toggling shell chrome updates visibility state")
    @MainActor
    func toggleShellChrome() async {
        let store = TestStore(
            initialState: WindowFeature.State(
                isSidebarVisible: true,
                isNavigatorCollapsed: false
            )
        ) {
            WindowFeature()
        }

        await store.send(.toggleSidebarVisibility) {
            $0.isSidebarVisible = false
        }

        await store.send(.toggleNavigatorCollapsed) {
            $0.isNavigatorCollapsed = true
        }
    }

    @Test("Shell coordination state is reducer-owned")
    @MainActor
    func shellCoordinationState() async {
        let selectedTabID = TabID()
        let previewTabID = TabID()
        let paneID = PaneID()
        let workspaceID = "/tmp/devys-project/workspaces/feature"
        let revealID = UUID(2)
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.uuid = .constant(revealID)
        }

        await store.send(
            .setWorkspaceLayout(
                workspaceID: workspaceID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: paneID,
                            tabIDs: [selectedTabID, previewTabID],
                            selectedTabID: selectedTabID
                        )
                    )
                )
            )
        ) {
            $0.workspaceShells[workspaceID] = WindowFeature.WorkspaceShell(
                focusedPaneID: paneID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: paneID,
                            tabIDs: [selectedTabID, previewTabID],
                            selectedTabID: selectedTabID
                        )
                    )
                )
            )
        }

        await store.send(.setWorkspaceFocusedPaneID(workspaceID: workspaceID, paneID: paneID))

        await store.send(.setSelectedTabID(selectedTabID)) {
            $0.selectedTabID = selectedTabID
        }

        await store.send(
            .setWorkspacePanePreviewTabID(
                workspaceID: workspaceID,
                paneID: paneID,
                tabID: previewTabID
            )
        ) {
            $0.workspaceShells[workspaceID]?.layout?.root = .pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: [selectedTabID, previewTabID],
                    selectedTabID: selectedTabID,
                    previewTabID: previewTabID
                )
            )
        }

        await store.send(.requestNavigatorReveal(workspaceID)) {
            $0.navigatorRevealRequest = WindowFeature.NavigatorRevealRequest(
                workspaceID: workspaceID,
                token: revealID
            )
        }
    }

    @Test("Workspace shell snapshots restore when switching workspaces")
    @MainActor
    func workspaceShellSnapshots() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspaceID = "/tmp/devys-project/workspaces/feature-a"
        let secondWorkspaceID = "/tmp/devys-project/workspaces/feature-b"
        let firstPaneID = PaneID()
        let secondPaneID = PaneID()
        let firstSelectedTabID = TabID()
        let secondPreviewTabID = TabID()
        let store = makeStore(repository: repository)

        await store.send(.selectWorkspace(firstWorkspaceID)) {
            $0.selectedWorkspaceID = firstWorkspaceID
        }

        await store.send(
            .setWorkspaceLayout(
                workspaceID: firstWorkspaceID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: firstPaneID,
                            tabIDs: [firstSelectedTabID],
                            selectedTabID: firstSelectedTabID
                        )
                    )
                )
            )
        ) {
            $0.workspaceShells[firstWorkspaceID] = WindowFeature.WorkspaceShell(
                focusedPaneID: firstPaneID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: firstPaneID,
                            tabIDs: [firstSelectedTabID],
                            selectedTabID: firstSelectedTabID
                        )
                    )
                )
            )
            $0.selectedTabID = firstSelectedTabID
        }

        await store.send(.showSidebar(.agents)) {
            $0.activeSidebar = .agents
            $0.isSidebarVisible = true
            $0.workspaceShells[firstWorkspaceID]?.activeSidebar = .agents
        }

        await store.send(.setSelectedTabID(firstSelectedTabID))

        await store.send(.selectWorkspace(secondWorkspaceID)) {
            $0.selectedWorkspaceID = secondWorkspaceID
            $0.selectedTabID = nil
            $0.activeSidebar = .agents
        }

        await store.send(
            .setWorkspaceLayout(
                workspaceID: secondWorkspaceID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: secondPaneID,
                            tabIDs: [secondPreviewTabID]
                        )
                    )
                )
            )
        ) {
            $0.workspaceShells[secondWorkspaceID] = WindowFeature.WorkspaceShell(
                activeSidebar: .files,
                focusedPaneID: secondPaneID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: secondPaneID,
                            tabIDs: [secondPreviewTabID]
                        )
                    )
                )
            )
        }

        await store.send(.setActiveSidebar(.files)) {
            $0.activeSidebar = .files
            $0.workspaceShells[secondWorkspaceID]?.activeSidebar = .files
        }

        await store.send(
            .setWorkspacePanePreviewTabID(
                workspaceID: secondWorkspaceID,
                paneID: secondPaneID,
                tabID: secondPreviewTabID
            )
        ) {
            $0.workspaceShells[secondWorkspaceID]?.layout?.root = .pane(
                WindowFeature.WorkspacePaneLayout(
                    id: secondPaneID,
                    tabIDs: [secondPreviewTabID],
                    previewTabID: secondPreviewTabID
                )
            )
        }

        await store.send(.selectWorkspace(firstWorkspaceID)) {
            $0.selectedWorkspaceID = firstWorkspaceID
            $0.selectedTabID = firstSelectedTabID
            $0.activeSidebar = .agents
            $0.workspaceShells[secondWorkspaceID] = WindowFeature.WorkspaceShell(
                activeSidebar: .files,
                focusedPaneID: secondPaneID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(
                        WindowFeature.WorkspacePaneLayout(
                            id: secondPaneID,
                            tabIDs: [secondPreviewTabID],
                            previewTabID: secondPreviewTabID
                        )
                    )
                )
            )
        }
    }

    @Test("Workspace shells store semantic tab contents per workspace")
    @MainActor
    func workspaceShellTabContents() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let tabID = TabID()
        let content = WorkspaceTabContent.editor(
            workspaceID: workspaceID,
            url: URL(fileURLWithPath: "/tmp/devys-project/workspaces/feature-a/File.swift")
        )
        let store = makeStore(repository: repository)

        await store.send(.selectWorkspace(workspaceID)) {
            $0.selectedWorkspaceID = workspaceID
        }

        await store.send(
            .setWorkspaceTabContent(
                workspaceID: workspaceID,
                tabID: tabID,
                content: content
            )
        ) {
            $0.workspaceShells[workspaceID] = WindowFeature.WorkspaceShell(
                activeSidebar: .files,
                tabContents: [tabID: content]
            )
        }

        await store.send(.removeWorkspaceTabContent(workspaceID: workspaceID, tabID: tabID)) {
            $0.workspaceShells[workspaceID]?.tabContents.removeValue(forKey: tabID)
        }
    }

    @Test("Workspace tab insertion and selection are reducer-owned")
    @MainActor
    func workspaceTabInsertionAndSelection() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let paneID = PaneID()
        let previewTabID = TabID()
        let permanentTabID = TabID()
        let store = makeStore(repository: repository)

        await store.send(.selectWorkspace(workspaceID)) {
            $0.selectedWorkspaceID = workspaceID
        }

        await store.send(
            .setWorkspaceLayout(
                workspaceID: workspaceID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(WindowFeature.WorkspacePaneLayout(id: paneID))
                )
            )
        ) {
            $0.workspaceShells[workspaceID] = WindowFeature.WorkspaceShell(
                focusedPaneID: paneID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .pane(WindowFeature.WorkspacePaneLayout(id: paneID))
                )
            )
        }

        await store.send(
            .insertWorkspaceTab(
                workspaceID: workspaceID,
                paneID: paneID,
                tabID: previewTabID,
                index: nil,
                isPreview: true
            )
        ) {
            $0.workspaceShells[workspaceID]?.focusedPaneID = paneID
            $0.workspaceShells[workspaceID]?.layout?.root = .pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: [previewTabID],
                    selectedTabID: previewTabID,
                    previewTabID: previewTabID
                )
            )
            $0.selectedTabID = previewTabID
        }

        await store.send(
            .insertWorkspaceTab(
                workspaceID: workspaceID,
                paneID: paneID,
                tabID: permanentTabID,
                index: nil,
                isPreview: false
            )
        ) {
            $0.workspaceShells[workspaceID]?.focusedPaneID = paneID
            $0.workspaceShells[workspaceID]?.layout?.root = .pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: [previewTabID, permanentTabID],
                    selectedTabID: permanentTabID,
                    previewTabID: previewTabID
                )
            )
            $0.selectedTabID = permanentTabID
        }

        await store.send(
            .selectWorkspaceTab(workspaceID: workspaceID, paneID: paneID, tabID: previewTabID)
        ) {
            $0.workspaceShells[workspaceID]?.focusedPaneID = paneID
            $0.workspaceShells[workspaceID]?.layout?.root = .pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: [previewTabID, permanentTabID],
                    selectedTabID: previewTabID,
                    previewTabID: previewTabID
                )
            )
            $0.selectedTabID = previewTabID
        }
    }

    @Test("Opening preview content reuses the pane preview tab in the reducer")
    @MainActor
    func openWorkspaceContentReusesPreviewTab() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let workspace = Worktree(
            name: "feature-a",
            detail: "feature-a",
            workingDirectory: URL(fileURLWithPath: workspaceID),
            repositoryRootURL: repository.rootURL
        )
        let paneID = PaneID()
        let previewTabID = TabID()
        let existingContent = WorkspaceTabContent.editor(
            workspaceID: workspaceID,
            url: URL(fileURLWithPath: "/tmp/devys-project/workspaces/feature-a/Old.swift")
        )
        let newContent = WorkspaceTabContent.editor(
            workspaceID: workspaceID,
            url: URL(fileURLWithPath: "/tmp/devys-project/workspaces/feature-a/New.swift")
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspaceID,
                workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                        tabContents: [previewTabID: existingContent],
                        focusedPaneID: paneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .pane(
                                WindowFeature.WorkspacePaneLayout(
                                    id: paneID,
                                    tabIDs: [previewTabID],
                                    selectedTabID: previewTabID,
                                    previewTabID: previewTabID
                                )
                            )
                        )
                    )
                ],
                selectedTabID: previewTabID
            )
        ) {
            WindowFeature()
        }

        await store.send(
            WindowFeature.Action.openWorkspaceContent(
                workspaceID: workspaceID,
                paneID: paneID,
                content: newContent,
                mode: WindowFeature.TabOpenMode.preview
            )
        ) {
            $0.workspaceShells[workspaceID]?.tabContents[previewTabID] = newContent
            $0.workspaceShells[workspaceID]?.focusedPaneID = paneID
            $0.workspaceShells[workspaceID]?.layout?.root = WindowFeature.WorkspaceLayoutNode.pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: [previewTabID],
                    selectedTabID: previewTabID,
                    previewTabID: previewTabID
                )
            )
            $0.selectedTabID = previewTabID
        }
    }

    @Test("Opening permanent content promotes a matching preview tab in the reducer")
    @MainActor
    func openWorkspaceContentPromotesPreviewTab() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let workspace = Worktree(
            name: "feature-a",
            detail: "feature-a",
            workingDirectory: URL(fileURLWithPath: workspaceID),
            repositoryRootURL: repository.rootURL
        )
        let paneID = PaneID()
        let previewTabID = TabID()
        let content = WorkspaceTabContent.editor(
            workspaceID: workspaceID,
            url: URL(fileURLWithPath: "/tmp/devys-project/workspaces/feature-a/File.swift")
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspaceID,
                workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                        tabContents: [previewTabID: content],
                        focusedPaneID: paneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .pane(
                                WindowFeature.WorkspacePaneLayout(
                                    id: paneID,
                                    tabIDs: [previewTabID],
                                    selectedTabID: previewTabID,
                                    previewTabID: previewTabID
                                )
                            )
                        )
                    )
                ],
                selectedTabID: previewTabID
            )
        ) {
            WindowFeature()
        }

        await store.send(
            WindowFeature.Action.openWorkspaceContent(
                workspaceID: workspaceID,
                paneID: paneID,
                content: content,
                mode: WindowFeature.TabOpenMode.permanent
            )
        ) {
            $0.workspaceShells[workspaceID]?.focusedPaneID = paneID
            $0.workspaceShells[workspaceID]?.layout?.root = WindowFeature.WorkspaceLayoutNode.pane(
                WindowFeature.WorkspacePaneLayout(
                    id: paneID,
                    tabIDs: [previewTabID],
                    selectedTabID: previewTabID
                )
            )
            $0.selectedTabID = previewTabID
        }
    }

    @Test("Opening already visible content focuses the existing tab instead of inserting a duplicate")
    @MainActor
    func openWorkspaceContentFocusesExistingTab() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let workspace = Worktree(
            name: "feature-a",
            detail: "feature-a",
            workingDirectory: URL(fileURLWithPath: workspaceID),
            repositoryRootURL: repository.rootURL
        )
        let firstPaneID = PaneID()
        let secondPaneID = PaneID()
        let existingTabID = TabID()
        let content = WorkspaceTabContent.gitDiff(
            workspaceID: workspaceID,
            path: "Sources/Feature/File.swift",
            isStaged: false
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [workspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: workspaceID,
                workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                        tabContents: [existingTabID: content],
                        focusedPaneID: secondPaneID,
                        layout: WindowFeature.WorkspaceLayout(
                            root: .split(
                                WindowFeature.WorkspaceSplitLayout(
                                    orientation: .horizontal,
                                    dividerPosition: 0.5,
                                    first: .pane(
                                        WindowFeature.WorkspacePaneLayout(
                                            id: firstPaneID,
                                            tabIDs: [existingTabID],
                                            selectedTabID: existingTabID
                                        )
                                    ),
                                    second: .pane(WindowFeature.WorkspacePaneLayout(id: secondPaneID))
                                )
                            )
                        )
                    )
                ]
            )
        ) {
            WindowFeature()
        }

        await store.send(
            WindowFeature.Action.openWorkspaceContent(
                workspaceID: workspaceID,
                paneID: secondPaneID,
                content: content,
                mode: WindowFeature.TabOpenMode.permanent
            )
        ) {
            $0.workspaceShells[workspaceID]?.focusedPaneID = firstPaneID
            $0.selectedTabID = existingTabID
        }
    }

    @Test("Reordering a tab within a pane stays reducer-owned")
    @MainActor
    func reorderWorkspaceTab() {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let paneID = PaneID()
        let firstTabID = TabID()
        let secondTabID = TabID()
        let previewTabID = TabID()
        var state = WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: paneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .pane(
                            WindowFeature.WorkspacePaneLayout(
                                id: paneID,
                                tabIDs: [firstTabID, secondTabID, previewTabID],
                                selectedTabID: secondTabID,
                                previewTabID: previewTabID
                            )
                        )
                    )
                )
            ],
            selectedTabID: secondTabID
        )
        state.selectedWorkspaceID = workspaceID
        let reducer = WindowFeature()

        _ = reducer.reduce(
            into: &state,
            action: .reorderWorkspaceTab(
                workspaceID: workspaceID,
                paneID: paneID,
                tabID: previewTabID,
                sourceIndex: 2,
                destinationIndex: 0
            )
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == paneID)
        #expect(state.selectedTabID == secondTabID)
        #expect(
            state.workspaceShells[workspaceID]?.layout?.root
                == .pane(
                    WindowFeature.WorkspacePaneLayout(
                        id: paneID,
                        tabIDs: [previewTabID, firstTabID, secondTabID],
                        selectedTabID: secondTabID,
                        previewTabID: previewTabID
                    )
                )
        )
    }

    @Test("Forward tab reorders preserve the intended destination index")
    @MainActor
    func reorderWorkspaceTabForward() {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let paneID = PaneID()
        let firstTabID = TabID()
        let secondTabID = TabID()
        let thirdTabID = TabID()
        var state = WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: paneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .pane(
                            WindowFeature.WorkspacePaneLayout(
                                id: paneID,
                                tabIDs: [firstTabID, secondTabID, thirdTabID],
                                selectedTabID: firstTabID
                            )
                        )
                    )
                )
            ],
            selectedTabID: firstTabID
        )
        state.selectedWorkspaceID = workspaceID
        let reducer = WindowFeature()

        _ = reducer.reduce(
            into: &state,
            action: .reorderWorkspaceTab(
                workspaceID: workspaceID,
                paneID: paneID,
                tabID: firstTabID,
                sourceIndex: 0,
                destinationIndex: 2
            )
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == paneID)
        #expect(state.selectedTabID == firstTabID)
        #expect(
            state.workspaceShells[workspaceID]?.layout?.root
                == .pane(
                    WindowFeature.WorkspacePaneLayout(
                        id: paneID,
                        tabIDs: [secondTabID, firstTabID, thirdTabID],
                        selectedTabID: firstTabID
                    )
                )
        )
    }

    @Test("Moving a tab across panes collapses an emptied source pane")
    @MainActor
    func moveWorkspaceTabAcrossPanes() {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let sourcePaneID = PaneID()
        let destinationPaneID = PaneID()
        let movedTabID = TabID()
        let existingDestinationTabID = TabID()
        var state = WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: sourcePaneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .split(
                            WindowFeature.WorkspaceSplitLayout(
                                orientation: .horizontal,
                                dividerPosition: 0.5,
                                first: .pane(
                                    WindowFeature.WorkspacePaneLayout(
                                        id: sourcePaneID,
                                        tabIDs: [movedTabID],
                                        selectedTabID: movedTabID
                                    )
                                ),
                                second: .pane(
                                    WindowFeature.WorkspacePaneLayout(
                                        id: destinationPaneID,
                                        tabIDs: [existingDestinationTabID],
                                        selectedTabID: existingDestinationTabID
                                    )
                                )
                            )
                        )
                    )
                )
            ],
            selectedTabID: movedTabID
        )
        state.selectedWorkspaceID = workspaceID
        let reducer = WindowFeature()

        _ = reducer.reduce(
            into: &state,
            action: .moveWorkspaceTab(
                workspaceID: workspaceID,
                tabID: movedTabID,
                sourcePaneID: sourcePaneID,
                destinationPaneID: destinationPaneID,
                index: nil
            )
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == destinationPaneID)
        #expect(state.selectedTabID == movedTabID)
        #expect(
            state.workspaceShells[workspaceID]?.layout?.root
                == .pane(
                    WindowFeature.WorkspacePaneLayout(
                        id: destinationPaneID,
                        tabIDs: [existingDestinationTabID, movedTabID],
                        selectedTabID: movedTabID
                    )
                )
        )
    }

    @Test("Splitting a pane with its preview tab preserves an empty source pane")
    @MainActor
    func splitWorkspacePaneWithPreviewTab() {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let originalPaneID = PaneID()
        let newPaneID = PaneID()
        let previewTabID = TabID()
        var state = WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: originalPaneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .pane(
                            WindowFeature.WorkspacePaneLayout(
                                id: originalPaneID,
                                tabIDs: [previewTabID],
                                selectedTabID: previewTabID,
                                previewTabID: previewTabID
                            )
                        )
                    )
                )
            ],
            selectedTabID: previewTabID
        )
        state.selectedWorkspaceID = workspaceID
        let reducer = WindowFeature()

        _ = reducer.reduce(
            into: &state,
            action: .splitWorkspacePaneWithTab(
                workspaceID: workspaceID,
                targetPaneID: originalPaneID,
                newPaneID: newPaneID,
                tabID: previewTabID,
                sourcePaneID: originalPaneID,
                sourceIndex: 0,
                orientation: .horizontal,
                insertion: .after
            )
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == newPaneID)
        #expect(state.selectedTabID == previewTabID)
        if case .split(let split)? = state.workspaceShells[workspaceID]?.layout?.root {
            #expect(split.orientation == .horizontal)
            #expect(split.dividerPosition == 0.5)
            #expect(split.first.paneLayout(for: originalPaneID)?.tabIDs == [])
            #expect(split.second.paneLayout(for: newPaneID)?.tabIDs == [previewTabID])
            #expect(split.second.paneLayout(for: newPaneID)?.selectedTabID == previewTabID)
            #expect(split.second.paneLayout(for: newPaneID)?.previewTabID == previewTabID)
        } else {
            Issue.record("Expected split layout after splitting pane with preview tab.")
        }
    }

    @Test("Workspace splits and pane closure are reducer-owned")
    @MainActor
    func workspaceSplitAndClosePane() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let originalPaneID = PaneID()
        let newPaneID = PaneID()
        let tabID = TabID()
        var state = WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: originalPaneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .pane(
                            WindowFeature.WorkspacePaneLayout(
                                id: originalPaneID,
                                tabIDs: [tabID],
                                selectedTabID: tabID
                            )
                        )
                    )
                )
            ],
            selectedTabID: tabID
        )
        state.selectedWorkspaceID = workspaceID
        let reducer = WindowFeature()

        _ = reducer.reduce(
            into: &state,
            action: .splitWorkspacePane(
                workspaceID: workspaceID,
                paneID: originalPaneID,
                newPaneID: newPaneID,
                orientation: .horizontal,
                insertion: .after
            )
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == newPaneID)
        #expect(state.selectedTabID == nil)
        if case .split(let split)? = state.workspaceShells[workspaceID]?.layout?.root {
            #expect(split.orientation == .horizontal)
            #expect(split.first.paneLayout(for: originalPaneID)?.tabIDs == [tabID])
            #expect(split.second.paneLayout(for: newPaneID)?.tabIDs == [])
        } else {
            Issue.record("Expected split layout after splitting pane.")
        }

        _ = reducer.reduce(
            into: &state,
            action: .closeWorkspacePane(workspaceID: workspaceID, paneID: newPaneID)
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == originalPaneID)
        #expect(state.selectedTabID == tabID)
        #expect(
            state.workspaceShells[workspaceID]?.layout?.root
                == .pane(
                    WindowFeature.WorkspacePaneLayout(
                        id: originalPaneID,
                        tabIDs: [tabID],
                        selectedTabID: tabID
                    )
                )
        )
    }

    @Test("Closing the last tab in a secondary pane collapses that pane")
    @MainActor
    func closingLastTabCollapsesSecondaryPane() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let firstPaneID = PaneID()
        let secondPaneID = PaneID()
        let firstTabID = TabID()
        let secondTabID = TabID()
        var state = WindowFeature.State(
            repositories: [repository],
            selectedRepositoryID: repository.id,
            workspaceShells: [
                workspaceID: WindowFeature.WorkspaceShell(
                    focusedPaneID: secondPaneID,
                    layout: WindowFeature.WorkspaceLayout(
                        root: .split(
                            WindowFeature.WorkspaceSplitLayout(
                                orientation: .horizontal,
                                dividerPosition: 0.5,
                                first: .pane(
                                    WindowFeature.WorkspacePaneLayout(
                                        id: firstPaneID,
                                        tabIDs: [firstTabID],
                                        selectedTabID: firstTabID
                                    )
                                ),
                                second: .pane(
                                    WindowFeature.WorkspacePaneLayout(
                                        id: secondPaneID,
                                        tabIDs: [secondTabID],
                                        selectedTabID: secondTabID
                                    )
                                )
                            )
                        )
                    )
                )
            ],
            selectedTabID: secondTabID
        )
        state.selectedWorkspaceID = workspaceID
        let reducer = WindowFeature()

        _ = reducer.reduce(
            into: &state,
            action: .closeWorkspaceTab(
                workspaceID: workspaceID,
                paneID: secondPaneID,
                tabID: secondTabID
            )
        )

        #expect(state.workspaceShells[workspaceID]?.focusedPaneID == firstPaneID)
        #expect(state.selectedTabID == firstTabID)
        #expect(
            state.workspaceShells[workspaceID]?.layout?.root
                == .pane(
                    WindowFeature.WorkspacePaneLayout(
                        id: firstPaneID,
                        tabIDs: [firstTabID],
                        selectedTabID: firstTabID
                    )
                )
        )
    }

    @Test("Split divider updates are reducer-owned")
    @MainActor
    func splitDividerUpdates() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let workspaceID = "/tmp/devys-project/workspaces/feature-a"
        let splitID = UUID()
        let firstPaneID = PaneID()
        let secondPaneID = PaneID()
        let store = makeStore(repository: repository)

        await store.send(.selectWorkspace(workspaceID)) {
            $0.selectedWorkspaceID = workspaceID
        }

        await store.send(
            .setWorkspaceLayout(
                workspaceID: workspaceID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .split(
                        WindowFeature.WorkspaceSplitLayout(
                            id: splitID,
                            orientation: .vertical,
                            dividerPosition: 0.5,
                            first: .pane(WindowFeature.WorkspacePaneLayout(id: firstPaneID)),
                            second: .pane(WindowFeature.WorkspacePaneLayout(id: secondPaneID))
                        )
                    )
                )
            )
        ) {
            $0.workspaceShells[workspaceID] = WindowFeature.WorkspaceShell(
                focusedPaneID: firstPaneID,
                layout: WindowFeature.WorkspaceLayout(
                    root: .split(
                        WindowFeature.WorkspaceSplitLayout(
                            id: splitID,
                            orientation: .vertical,
                            dividerPosition: 0.5,
                            first: .pane(WindowFeature.WorkspacePaneLayout(id: firstPaneID)),
                            second: .pane(WindowFeature.WorkspacePaneLayout(id: secondPaneID))
                        )
                    )
                )
            )
        }

        await store.send(
            .setWorkspaceSplitDividerPosition(
                workspaceID: workspaceID,
                splitID: splitID,
                position: 0.7
            )
        ) {
            $0.workspaceShells[workspaceID]?.layout?.root = .split(
                WindowFeature.WorkspaceSplitLayout(
                    id: splitID,
                    orientation: .vertical,
                    dividerPosition: 0.7,
                    first: .pane(WindowFeature.WorkspacePaneLayout(id: firstPaneID)),
                    second: .pane(WindowFeature.WorkspacePaneLayout(id: secondPaneID))
                )
            )
        }

        await store.send(
            .setWorkspaceSplitDividerPosition(
                workspaceID: workspaceID,
                splitID: splitID,
                position: 5
            )
        ) {
            $0.workspaceShells[workspaceID]?.layout?.root = .split(
                WindowFeature.WorkspaceSplitLayout(
                    id: splitID,
                    orientation: .vertical,
                    dividerPosition: 0.9,
                    first: .pane(WindowFeature.WorkspacePaneLayout(id: firstPaneID)),
                    second: .pane(WindowFeature.WorkspacePaneLayout(id: secondPaneID))
                )
            )
        }
    }

    @Test("Operational snapshot updates become reducer-owned workspace state")
    @MainActor
    func workspaceOperationalSnapshotUpdated() async {
        let workspaceID = "/tmp/devys-project/workspaces/ops"
        let terminalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let now = Date(timeIntervalSince1970: 100)
        var state = WindowFeature.State()

        try? await withDependencies {
            $0.date.now = now
        } operation: {
            let reducer = WindowFeature()
            _ = reducer.reduce(
                into: &state,
                action: .workspaceOperationalSnapshotUpdated(
                    WorkspaceOperationalSnapshot(
                        metadataEntriesByWorkspaceID: [
                            workspaceID: WorktreeInfoEntry(branchName: "feature/ops")
                        ],
                        unreadTerminalIDsByWorkspaceID: [workspaceID: Set([terminalID])]
                    )
                )
            )
        }

        #expect(
            state.operational.metadataEntriesByWorkspaceID
                == [workspaceID: WorktreeInfoEntry(branchName: "feature/ops")]
        )
        #expect(
            state.operational.unreadTerminalIDsByWorkspaceID
                == [workspaceID: Set([terminalID])]
        )
        let notifications = state.operational.notifications(for: workspaceID)
        #expect(notifications.count == 1)
        #expect(notifications[0].source == .terminal)
        #expect(notifications[0].kind == .unread)
        #expect(notifications[0].terminalID == terminalID)
        #expect(notifications[0].createdAt == now)
    }

    @Test("Marking terminal attention read clears reducer state and calls the client")
    @MainActor
    func markTerminalAttentionRead() async {
        let workspaceID = "/tmp/devys-project/workspaces/ops"
        let terminalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let notificationID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let recorder = WorkspaceOperationalMarkReadRecorder()
        let store = TestStore(
            initialState: {
                var state = WindowFeature.State()
                state.operational.unreadTerminalIDsByWorkspaceID = [workspaceID: Set([terminalID])]
                state.operational.notificationsByWorkspaceID = [
                    workspaceID: [
                        WorkspaceAttentionNotification(
                            id: notificationID,
                            workspaceID: workspaceID,
                            source: .terminal,
                            kind: .unread,
                            terminalID: terminalID,
                            title: "Terminal needs attention",
                            subtitle: nil,
                            createdAt: Date(timeIntervalSince1970: 100)
                        )
                    ]
                ]
                return state
            }()
        ) {
            WindowFeature()
        } withDependencies: {
            $0.workspaceOperationalClient.markTerminalRead = { workspaceID, terminalID in
                recorder.record(workspaceID: workspaceID, terminalID: terminalID)
            }
        }

        await store.send(.markTerminalAttentionRead(workspaceID: workspaceID, terminalID: terminalID)) {
            $0.operational.unreadTerminalIDsByWorkspaceID = [:]
            $0.operational.notificationsByWorkspaceID = [:]
        }

        #expect(recorder.calls == ["\(workspaceID)|\(terminalID.uuidString)"])
    }

    @Test("Starting workspace operational observation begins the streams and performs a reducer-owned sync")
    @MainActor
    func startWorkspaceOperationalObservation() async {
        let recorder = WorkspaceOperationalSyncRecorder()
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.workspaceOperationalClient.updates = {
                AsyncStream { _ in }
            }
            $0.workspaceOperationalClient.sync = { _, mode in
                recorder.record(mode)
            }
            $0.workspaceAttentionIngressClient.updates = {
                AsyncStream { _ in }
            }
        }
        store.exhaustivity = .off

        await store.send(.startWorkspaceOperationalObservation)
        await Task.yield()

        #expect(recorder.modes == [.all])
    }

    @Test("Attention ingress becomes reducer-owned notification state")
    @MainActor
    func workspaceAttentionIngressReceived() async {
        let workspaceID = "/tmp/devys-project/workspaces/ops"
        let now = Date(timeIntervalSince1970: 250)
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(
            .workspaceAttentionIngressReceived(
                WorkspaceAttentionIngressPayload(
                    workspaceID: workspaceID,
                    source: .claude,
                    kind: .waiting,
                    terminalID: nil,
                    title: "Claude needs approval",
                    subtitle: "Permission request"
                )
            )
        )

        let notifications = store.state.operational.notificationsByWorkspaceID[workspaceID] ?? []
        #expect(notifications.count == 1)
        #expect(notifications[0].workspaceID == workspaceID)
        #expect(notifications[0].source == .claude)
        #expect(notifications[0].kind == .waiting)
        #expect(notifications[0].title == "Claude needs approval")
        #expect(notifications[0].subtitle == "Permission request")
        #expect(notifications[0].createdAt == now)
    }

    @Test("Notification preferences immediately clear reducer-owned attention by policy")
    @MainActor
    func setWorkspaceNotificationPreferences() async {
        let workspaceID = "/tmp/devys-project/workspaces/ops"
        let terminalID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let store = TestStore(
            initialState: {
                var state = WindowFeature.State()
                state.operational.notificationsByWorkspaceID = [
                    workspaceID: [
                        WorkspaceAttentionNotification(
                            workspaceID: workspaceID,
                            source: .terminal,
                            kind: .unread,
                            terminalID: terminalID,
                            title: "Terminal needs attention",
                            createdAt: Date(timeIntervalSince1970: 100)
                        ),
                        WorkspaceAttentionNotification(
                            workspaceID: workspaceID,
                            source: .claude,
                            kind: .waiting,
                            title: "Claude needs approval",
                            createdAt: Date(timeIntervalSince1970: 200)
                        )
                    ]
                ]
                state.operational.unreadTerminalIDsByWorkspaceID = [workspaceID: Set([terminalID])]
                return state
            }()
        ) {
            WindowFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 300)
        }

        await store.send(.setWorkspaceNotificationPreferences(terminalActivity: false, agentActivity: false)) {
            $0.isTerminalActivityNotificationsEnabled = false
            $0.isAgentActivityNotificationsEnabled = false
            $0.operational.notificationsByWorkspaceID = [:]
            $0.operational.unreadTerminalIDsByWorkspaceID = [workspaceID: Set([terminalID])]
        }
    }

    @Test("Run launch completion stores reducer-owned run lifecycle state")
    @MainActor
    func runProfileLaunchCompleted() async {
        let workspaceID = "/tmp/devys-project/workspaces/ops"
        let profileID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let terminalID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let processID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        }

        await store.send(
            .runProfileLaunchCompleted(
                WindowFeature.RunProfileLaunchResult(
                    workspaceID: workspaceID,
                    profileID: profileID,
                    terminalIDs: [terminalID],
                    backgroundProcessIDs: [processID],
                    failures: []
                )
            )
        ) {
            $0.operational.runStatesByWorkspaceID = [
                workspaceID: WorkspaceRunState(
                    profileID: profileID,
                    terminalIDs: Set([terminalID]),
                    backgroundProcessIDs: Set([processID])
                )
            ]
        }
    }

    @MainActor
    private func makeStore(repository: Repository) -> TestStoreOf<WindowFeature> {
        TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                selectedRepositoryID: repository.id
            )
        ) {
            WindowFeature()
        }
    }
}

@MainActor
private final class WorkspaceOperationalMarkReadRecorder {
    private(set) var calls: [String] = []

    func record(workspaceID: Workspace.ID?, terminalID: UUID) {
        calls.append("\(workspaceID ?? "nil")|\(terminalID.uuidString)")
    }
}

@MainActor
private final class WorkspaceOperationalSyncRecorder {
    private(set) var modes: [WorkspaceOperationalSyncMode] = []

    func record(_ mode: WorkspaceOperationalSyncMode) {
        modes.append(mode)
    }
}
