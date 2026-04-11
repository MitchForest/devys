// ContentView+Actions.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import Split
import SwiftUI
import Workspace
import Editor

@MainActor
extension ContentView {
    private struct RepositoryImportFailure {
        let selectedURL: URL
        let message: String
    }

    // MARK: - Save Actions
    
    /// Saves the currently focused editor tab.
    /// Called by Cmd+S menu action.
    func saveActiveEditor() {
        guard let activeTabId = selectedTabId,
              let content = tabContents[activeTabId],
              case .editor = content,
              let session = editorSessions[activeTabId] else {
            // No editor tab is focused, try responder chain as fallback
            NSApp.sendAction(#selector(MetalEditorView.saveDocument(_:)), to: nil, from: nil)
            return
        }
        
        guard session.isDirty else {
            // Nothing to save
            return
        }
        
        Task { @MainActor in
            do {
                try await session.save()
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Save Failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    /// Saves the editor tab as a new file.
    func saveActiveEditorAs() {
        guard let activeTabId = selectedTabId,
              let content = tabContents[activeTabId],
              case .editor = content,
              let session = editorSessions[activeTabId],
              let document = session.document else {
            NSApp.sendAction(#selector(MetalEditorView.saveDocumentAs(_:)), to: nil, from: nil)
            return
        }
        
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.fileURL?.lastPathComponent ?? "Untitled"
        panel.message = "Save file"
        panel.prompt = "Save"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let canonicalURL = canonicalEditorSessionURL(url)
        if let sharedTargetSession = editorSessionPool.session(for: canonicalURL),
           sharedTargetSession !== session,
           sharedTargetSession.isDirty {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Save Failed"
            alert.informativeText = "The destination file is already open with unsaved changes."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        Task { @MainActor in
            do {
                let io = DefaultDocumentIOService()
                try await io.save(content: document.content, to: url)
                document.isDirty = false
                if let sharedTargetSession = editorSessionPool.session(for: canonicalURL),
                   sharedTargetSession !== session {
                    sharedTargetSession.reload()
                }
                updateEditorTabURL(tabId: activeTabId, newURL: url)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Save Failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @discardableResult
    func createTab(in paneId: PaneID, content: TabContent) -> TabID? {
        // Get title and icon from session if available, otherwise use fallbacks
        let title = tabMetadata(for: content).title
        let icon = tabMetadata(for: content).icon
        let activityIndicator = tabActivityIndicator()

        if let tabId = controller.createTab(
            title: title,
            icon: icon,
            activityIndicator: activityIndicator,
            inPane: paneId
        ) {
            setTabContent(content, for: tabId)
            tabPresentationById[tabId] = currentTabPresentation(for: content, tabId: tabId)
            selectTab(tabId)
            return tabId
        }

        return nil
    }

    func requestOpenRepository() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.message = "Choose one or more local projects to add"
            panel.prompt = "Add Project"

            guard panel.runModal() == .OK else { return }

            let selections = panel.urls.map(\.standardizedFileURL)
            let resolution = await resolveRepositories(from: selections)

            if !resolution.failures.isEmpty {
                showRepositoryImportFailures(resolution.failures)
            }

            guard !resolution.repositories.isEmpty else { return }
            await openRepositories(resolution.repositories)
        }
    }

    func openRepository(_ url: URL) async {
        let resolution = await resolveRepositories(from: [url.standardizedFileURL])

        if !resolution.failures.isEmpty {
            showRepositoryImportFailures(resolution.failures)
        }

        guard !resolution.repositories.isEmpty else { return }
        await openRepositories(resolution.repositories)
    }

    func presentWorkspaceCreation(
        for repositoryID: Repository.ID,
        mode: WorkspaceCreationMode = .newBranch
    ) {
        guard let repository = workspaceCatalog.repository(for: repositoryID) else {
            return
        }
        workspaceCreationRequest = WorkspaceCreationPresentationRequest(
            repository: repository,
            mode: mode
        )
    }

    // MARK: - Sidebar + Workspace Actions

    func showSidebarItem(_ item: WorkspaceSidebarMode) {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeSidebarItem = item
        }
        runtimeRegistry.activeShellState?.sidebarMode = item
        runtimeRegistry.setFilesSidebarVisible(item == .files)
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isSidebarVisible.toggle()
        }
        runtimeRegistry.setFilesSidebarVisible(isSidebarVisible)
    }

    func toggleNavigator() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isNavigatorCollapsed.toggle()
        }
        UserDefaults.standard.set(isNavigatorCollapsed, forKey: "com.devys.navigator.collapsed")
    }

    func selectWorkspace(at index: Int) {
        let workspaces = visibleNavigatorWorkspaces
        guard index >= 0, index < workspaces.count else { return }

        let target = workspaces[index]
        Task { @MainActor in
            await selectWorkspace(target.workspace.id, in: target.repositoryID)
        }
    }

    func selectAdjacentWorkspace(offset: Int) {
        let workspaces = visibleNavigatorWorkspaces
        guard !workspaces.isEmpty else { return }

        guard let visibleWorkspaceID,
              let currentIndex = workspaces.firstIndex(where: { $0.workspace.id == visibleWorkspaceID }) else {
            let fallbackIndex = offset >= 0 ? 0 : max(0, workspaces.count - 1)
            let target = workspaces[fallbackIndex]
            Task { @MainActor in
                await selectWorkspace(target.workspace.id, in: target.repositoryID)
            }
            return
        }

        let nextIndex = max(0, min(workspaces.count - 1, currentIndex + offset))
        guard nextIndex != currentIndex else { return }

        let target = workspaces[nextIndex]
        Task { @MainActor in
            await selectWorkspace(target.workspace.id, in: target.repositoryID)
        }
    }

    func revealCurrentWorkspaceInNavigator() {
        guard let visibleWorkspaceID else { return }
        navigatorRevealRequest = NavigatorRevealRequest(
            workspaceID: visibleWorkspaceID,
            token: UUID()
        )
    }

    func openShellForSelectedWorkspace() {
        guard let worktree = activeWorktree else { return }
        Task { @MainActor in
            let trace = WorkspacePerformanceRecorder.begin(
                "terminal-launch",
                context: [
                    "workspace_id": worktree.id,
                    "source": "shell"
                ]
            )
            do {
                let session = try await createWorkspaceTerminalSession(
                    in: worktree.id,
                    workingDirectory: worktree.workingDirectory
                )
                openInPermanentTab(content: .terminal(workspaceID: worktree.id, id: session.id))
                persistTerminalRelaunchSnapshotIfNeeded()
                WorkspacePerformanceRecorder.end(trace)
            } catch {
                WorkspacePerformanceRecorder.end(
                    trace,
                    outcome: "failure",
                    context: ["error": error.localizedDescription]
                )
                showLauncherUnavailableAlert(title: "Shell Unavailable", message: error.localizedDescription)
            }
        }
    }

    func openRepositorySettings() {
        openInPermanentTab(content: .settings)
    }

    var visibleNavigatorWorkspaces: [(repositoryID: Repository.ID, workspace: Worktree)] {
        workspaceCatalog.visibleNavigatorWorkspaces()
    }

    func showLauncherUnavailableAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func confirmCloseCurrentRepository() async -> Bool {
        let dirtySessions = uniqueEditorSessions.filter { $0.isDirty }
        if !dirtySessions.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Save changes before opening a new repository?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let success = await saveDirtyEditors(dirtySessions)
                if !success {
                    let errorAlert = NSAlert()
                    errorAlert.alertStyle = .critical
                    errorAlert.messageText = "Save Failed"
                    errorAlert.informativeText = "One or more files could not be saved."
                    errorAlert.addButton(withTitle: "OK")
                    errorAlert.runModal()
                    return false
                }
                return true
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Switch repositories?"
        alert.informativeText = "This will close all tabs and switch the active repository."
        alert.addButton(withTitle: "Add Repository")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func saveDirtyEditors(_ sessions: [EditorSession]) async -> Bool {
        var success = true
        for session in sessions {
            do {
                try await session.save()
            } catch {
                success = false
            }
        }
        return success
    }

    func openRepositories(_ repositories: [Repository]) async {
        let trace = WorkspacePerformanceRecorder.begin(
            "repository-open",
            context: ["repository_count": "\(repositories.count)"]
        )
        var traceContext: [String: String] = [:]
        defer {
            WorkspacePerformanceRecorder.end(trace, context: traceContext)
        }
        var seenRepositoryIDs: Set<Repository.ID> = []
        let uniqueRepositories = repositories.filter { repository in
            seenRepositoryIDs.insert(repository.id).inserted
        }
        guard let lastRepository = uniqueRepositories.last else { return }

        let shouldSwitchActiveRepository = workspaceCatalog.selectedRepositoryID != lastRepository.id

        if shouldSwitchActiveRepository {
            if workspaceCatalog.selectedRepositoryID != nil {
                let shouldReplace = await confirmCloseCurrentRepository()
                guard shouldReplace else { return }
            }
            persistVisibleWorkspaceState()
            resetWorkspaceState()
        }

        for repository in uniqueRepositories {
            workspaceCatalog.importRepository(repository)
            recentRepositoriesService.add(repository.rootURL)
        }
        await workspaceCatalog.refreshRepositories(uniqueRepositories.map(\.id))
        syncCatalogRuntimeState()

        if shouldSwitchActiveRepository,
           let selectedWorktree = selectedCatalogWorktree {
            restoreWorkspaceState(for: selectedWorktree)
        }

        traceContext = [
            "imported_repository_count": "\(uniqueRepositories.count)",
            "selected_repository_id": lastRepository.id
        ]
    }

    private func resolveRepositories(
        from selectedURLs: [URL]
    ) async -> (repositories: [Repository], failures: [RepositoryImportFailure]) {
        var repositories: [Repository] = []
        var failures: [RepositoryImportFailure] = []

        for selectedURL in selectedURLs {
            do {
                let repository = try await container.repositoryDiscoveryService.resolveRepository(
                    from: selectedURL
                )
                repositories.append(repository)
            } catch {
                failures.append(
                    RepositoryImportFailure(
                        selectedURL: selectedURL,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return (repositories, failures)
    }

    private func showRepositoryImportFailures(_ failures: [RepositoryImportFailure]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some selections could not be added"
        alert.informativeText = """
        \(failures.map { "\($0.selectedURL.path)\n\($0.message)" }.joined(separator: "\n\n"))
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func resetWorkspaceState() {
        tabContents.removeAll()
        tabPresentationById.removeAll()
        editorSessions.removeAll()
        editorSessionPool = EditorSessionPool()
        selectedTabId = nil
        previewTabId = nil
        closeBypass.removeAll()
        closeInFlight.removeAll()

        controller = ContentView.makeSplitController()
        configureSplitDelegate()
        applyDefaultLayout()
        controller.populateEmptyPanesWithWelcomeTabs()
        activeSidebarItem = .files
        runtimeRegistry.deactivateActiveWorkspace()
    }

    func applyDefaultLayout() {
        let layout = layoutPersistenceService.loadDefaultLayout()
        applyLayout(layout)
    }

    func handleCreatedWorkspaces(
        _ workspaces: [Workspace],
        in repository: Repository
    ) async {
        await refreshRepositoryCatalog(repositoryID: repository.id)

        if let workspace = workspaces.last {
            await selectWorkspace(workspace.id, in: repository.id)
            return
        }

        await selectRepository(repository.id)
    }
}
