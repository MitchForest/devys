// ContentView+Actions.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import AppFeatures
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
              case .editor(let workspaceID, _) = content,
              let session = editorSessions[activeTabId],
              let document = session.document,
              let editorSessionPool = editorSessionPool(for: workspaceID) else {
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
    func createTab(
        in paneId: PaneID,
        content: WorkspaceTabContent,
        isPreview: Bool = false
    ) -> TabID? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        // Get title and icon from session if available, otherwise use fallbacks
        let title = tabMetadata(for: content).title
        let icon = tabMetadata(for: content).icon
        let activityIndicator = tabActivityIndicator()
        let tabId = TabID()
        let insertIndex = insertionIndexForNewTab(in: paneId, workspaceID: workspaceID)

        store.send(
            .insertWorkspaceTab(
                workspaceID: workspaceID,
                paneID: paneId,
                tabID: tabId,
                index: insertIndex,
                isPreview: isPreview
            )
        )
        setTabContent(content, for: tabId)
        tabPresentationById[tabId] = TabPresentationState(
            title: title,
            icon: icon,
            isPreview: isPreview,
            isDirty: false,
            activityIndicator: activityIndicator
        )
        renderWorkspaceLayout(for: workspaceID)
        selectTab(tabId)
        return tabId
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
        store.send(.presentWorkspaceCreation(repositoryID: repositoryID, mode: mode))
    }

    // MARK: - Sidebar + Workspace Actions

    func showSidebarItem(_ item: WorkspaceSidebarMode) {
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            store.send(.showSidebar(item.windowSidebar))
        }
    }

    func toggleSidebar() {
        _ = withAnimation(.easeInOut(duration: 0.25)) {
            store.send(.toggleSidebarVisibility)
        }
    }

    func openShellForSelectedWorkspace(preferredPaneID: PaneID? = nil) {
        if isRemoteWorkspaceSelected {
            store.send(.requestOpenRemoteTerminal(preferredPaneID: preferredPaneID))
            return
        }

        guard let worktree = selectedCatalogWorktree else { return }
        focusWorkspacePaneIfNeeded(preferredPaneID, workspaceID: worktree.id)
        Task { @MainActor in
            let trace = WorkspacePerformanceRecorder.begin(
                "terminal-launch",
                context: [
                    "workspace_id": worktree.id,
                    "source": "shell"
                ]
            )
            let session = createPendingHostedTerminalSession(
                in: worktree.id,
                workingDirectory: worktree.workingDirectory,
                traceSource: "shell",
                launchProfile: .fastShell,
                openMode: "permanent"
            )
            do {
                try presentHostedTerminalTab(
                    session: session,
                    workspaceID: worktree.id,
                    preferredPaneID: preferredPaneID,
                    failureMessage: "Could not open a terminal tab."
                )
                try await startPendingHostedTerminalSession(
                    session,
                    in: worktree.id,
                    workingDirectory: worktree.workingDirectory,
                    launchProfile: .fastShell,
                    traceSource: "shell"
                )
                persistTerminalRelaunchSnapshotIfNeeded()
                WorkspacePerformanceRecorder.end(trace)
            } catch {
                failShellLaunch(trace: trace, error: error)
            }
        }
    }

    func openRepositorySettings() {
        openInPermanentTab(content: .settings)
    }

    func focusWorkspacePaneIfNeeded(
        _ preferredPaneID: PaneID?,
        workspaceID: Workspace.ID
    ) {
        guard let preferredPaneID else { return }
        store.send(.setWorkspaceFocusedPaneID(workspaceID: workspaceID, paneID: preferredPaneID))
        renderWorkspaceLayout(for: workspaceID)
    }

    private func failShellLaunch(
        trace: WorkspacePerformanceTrace,
        error: Error
    ) {
        WorkspacePerformanceRecorder.end(
            trace,
            outcome: "failure",
            context: ["error": error.localizedDescription]
        )
        showLauncherUnavailableAlert(
            title: "Shell Unavailable",
            message: error.localizedDescription
        )
    }

    func openFilePickerForSelectedWorkspace(in paneID: PaneID) {
        guard let workspaceID = selectedWorkspaceID,
              let workingDirectory = activeWorktree?.workingDirectory else {
            return
        }

        store.send(.setWorkspaceFocusedPaneID(workspaceID: workspaceID, paneID: paneID))
        renderWorkspaceLayout(for: workspaceID)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = workingDirectory
        panel.message = "Choose a file to open in this pane"
        panel.prompt = "Open"

        guard panel.runModal() == .OK,
              let url = panel.url?.standardizedFileURL else {
            return
        }

        openInPermanentTab(content: .editor(workspaceID: workspaceID, url: url))
    }

    var visibleNavigatorWorkspaces: [(repositoryID: Repository.ID, workspace: Worktree)] {
        store.repositories.flatMap { repository in
            (store.worktreesByRepository[repository.id] ?? []).compactMap { worktree in
                let isArchived = store.workspaceStatesByID[worktree.id]?.isArchived == true
                return isArchived ? nil : (repository.id, worktree)
            }
        }
    }

    func showLauncherUnavailableAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func confirmCloseCurrentRepository(
        dirtyPromptTitle: String = "Save changes before opening a new repository?",
        dirtyPromptMessage: String = "Your changes will be lost if you don't save them.",
        confirmationTitle: String = "Switch repositories?",
        confirmationMessage: String = "This will close all tabs and switch the active repository.",
        confirmationButtonTitle: String = "Add Repository"
    ) async -> Bool {
        let dirtySessions = uniqueEditorSessions.filter { $0.isDirty }
        if !dirtySessions.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = dirtyPromptTitle
            alert.informativeText = dirtyPromptMessage
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
        alert.messageText = confirmationTitle
        alert.informativeText = confirmationMessage
        alert.addButton(withTitle: confirmationButtonTitle)
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

        let shouldSwitchActiveRepository = selectedRepositoryID != lastRepository.id
        let previousSelectedRepositoryID = selectedRepositoryID

        if shouldSwitchActiveRepository {
            if selectedRepositoryID != nil {
                let shouldReplace = await confirmCloseCurrentRepository()
                guard shouldReplace else { return }
            }
            persistVisibleWorkspaceState()
            resetWorkspaceState()
        }

        await store.send(.openResolvedRepositories(repositories)).finish()
        await refreshRepositoryCatalogs(uniqueRepositories.map(\.id))

        if previousSelectedRepositoryID != selectedRepositoryID,
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
        clearVisibleWorkspaceTabContents()
        tabPresentationById.removeAll()
        editorSessions.removeAll()
        store.send(.selectWorkspace(nil))
        closeBypass.removeAll()
        closeInFlight.removeAll()

        controller = ContentView.makeSplitController()
        configureSplitDelegate()
        applyDefaultLayout()
        store.send(.setActiveSidebar(.files))
        runtimeRegistry.deactivateActiveWorkspace()
    }

    func applyDefaultLayout(workspaceID: Workspace.ID? = nil) {
        let layout = layoutPersistenceService.loadDefaultLayout()
        applyLayout(layout, workspaceID: workspaceID)
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

extension WorkspaceSidebarMode {
    var windowSidebar: WindowFeature.Sidebar {
        switch self {
        case .files:
            .files
        case .agents:
            .agents
        }
    }
}
