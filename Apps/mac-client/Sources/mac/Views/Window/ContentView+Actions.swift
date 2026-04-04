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
        let (title, icon) = tabMetadata(for: content)
        let activityIndicator = tabActivityIndicator()

        if let tabId = controller.createTab(
            title: title,
            icon: icon,
            activityIndicator: activityIndicator,
            inPane: paneId
        ) {
            setTabContent(content, for: tabId)
            selectTab(tabId)
            return tabId
        }

        return nil
    }

    func createTerminal() {
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        if let paneId = targetPane {
            let session = createTerminalSession(
                workingDirectory: defaultTerminalWorkingDirectory()
            )
            createTab(in: paneId, content: .terminal(id: session.id))
        }
    }

    func requestOpenFolder() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose a folder to open"
            panel.prompt = "Open"

            guard panel.runModal() == .OK, let url = panel.url else { return }
            await openFolder(url)
        }
    }

    func openFolder(_ url: URL) async {
        if let currentFolder = windowState.folder {
            if currentFolder == url { return }
            let shouldReplace = await confirmCloseCurrentFolder()
            guard shouldReplace else { return }
        }

        resetWorkspaceState()
        windowState.openFolder(url)
        recentFoldersService.add(url)
        applyDefaultLayout()
        
        // Create welcome tabs for empty panes after layout is applied
        controller.populateEmptyPanesWithWelcomeTabs()

        withAnimation(.easeInOut(duration: 0.2)) {
            activeSidebarItem = .files
        }
    }

    // MARK: - Sidebar + Worktree Shortcuts

    func showSidebarItem(_ item: SidebarItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeSidebarItem = item
        }
    }

    func selectWorktree(at index: Int) {
        guard let manager = worktreeManager else { return }
        let worktrees = manager.orderedWorktrees
        guard index >= 0, index < worktrees.count else { return }
        manager.selectWorktree(worktrees[index].id)
    }

    // MARK: - Run Commands

    func runSelectedWorktreeCommand() {
        guard let worktree = worktreeManager?.selectedWorktree else { return }
        let repositoryRoot = worktree.repositoryRootURL
        let settings = commandSettingsStore.settings(for: repositoryRoot)
        let existingCommand = settings.runCommand?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingCommand, !existingCommand.isEmpty {
            openTerminalForRunCommand(existingCommand, worktree: worktree)
            return
        }

        guard let newCommand = promptForRunCommand(
            defaultValue: settings.runCommand,
            worktreeName: worktree.name
        ) else { return }
        var updated = settings
        updated.runCommand = newCommand
        commandSettingsStore.updateSettings(updated, for: repositoryRoot)
        openTerminalForRunCommand(newCommand, worktree: worktree)
    }

    func editSelectedWorktreeRunCommand() {
        guard let worktree = worktreeManager?.selectedWorktree else { return }
        let repositoryRoot = worktree.repositoryRootURL
        let settings = commandSettingsStore.settings(for: repositoryRoot)
        guard let newCommand = promptForRunCommand(
            defaultValue: settings.runCommand,
            worktreeName: worktree.name
        ) else { return }
        commandSettingsStore.updateRunCommand(newCommand, for: repositoryRoot)
    }

    func clearSelectedWorktreeRunCommand() {
        guard let worktree = worktreeManager?.selectedWorktree else { return }
        commandSettingsStore.updateRunCommand(nil, for: worktree.repositoryRootURL)
    }

    func stopSelectedWorktreeCommand() {
        guard let worktree = worktreeManager?.selectedWorktree else { return }
        guard let state = runCommandStore.state(for: worktree.id),
              let session = terminalSessions[state.terminalId]
        else {
            return
        }

        session.shutdown()
        runCommandStore.markStopped(worktreeId: worktree.id)
    }

    private func promptForRunCommand(defaultValue: String?, worktreeName: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Set Run Command"
        alert.informativeText = "Enter the command to run for \(worktreeName)."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = defaultValue ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let command = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    private func openTerminalForRunCommand(_ command: String, worktree: Worktree) {
        let session = createTerminalSession(
            workingDirectory: worktree.workingDirectory,
            requestedCommand: command
        )
        runCommandStore.setRunning(worktreeId: worktree.id, terminalId: session.id)
        openInPermanentTab(content: .terminal(id: session.id))
    }

    private func defaultTerminalWorkingDirectory() -> URL? {
        if let selectedWorktree = worktreeManager?.selectedWorktree {
            return selectedWorktree.workingDirectory
        }

        return windowState.folder
    }

    private func confirmCloseCurrentFolder() async -> Bool {
        let dirtySessions = uniqueEditorSessions.filter { $0.isDirty }
        if !dirtySessions.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Save changes before opening a new folder?"
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
        alert.messageText = "Close current folder?"
        alert.informativeText = "This will close all tabs and open a new folder."
        alert.addButton(withTitle: "Open Folder")
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

    private func resetWorkspaceState() {
        for (tabId, content) in tabContents {
            cleanupSession(for: content, tabId: tabId)
        }

        tabContents.removeAll()
        editorSessions.removeAll()
        editorSessionPool = EditorSessionPool()
        terminalSessions.removeAll()
        runCommandStore.clear()
        selectedTabId = nil
        previewTabId = nil
        closeBypass.removeAll()
        closeInFlight.removeAll()

        controller = ContentView.makeSplitController()
        configureSplitDelegate()
    }

    private func applyDefaultLayout() {
        let layout = layoutPersistenceService.loadDefaultLayout()
        applyLayout(layout)
    }
}
