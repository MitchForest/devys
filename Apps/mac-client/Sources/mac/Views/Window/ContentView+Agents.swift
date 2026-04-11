import ACPClientKit
import Foundation
import Git
import Split
import Workspace

@MainActor
extension ContentView {
    func openDefaultOrPromptAgentForSelectedWorkspace(
        initialAttachments: [AgentAttachment] = [],
        preferredPaneID: PaneID? = nil
    ) {
        guard let worktree = activeWorktree else { return }

        if let configuredHarness = appSettings.agent.defaultHarness,
           let kind = agentKind(forHarness: configuredHarness) {
            openAgentSession(
                kind,
                workspaceID: worktree.id,
                initialAttachments: initialAttachments,
                preferredPaneID: preferredPaneID
            )
            return
        }

        agentLaunchRequest = AgentLaunchPresentationRequest(
            workspaceID: worktree.id,
            initialAttachments: initialAttachments,
            preferredPaneID: preferredPaneID,
            pendingSessionID: nil,
            pendingTabID: nil
        )
    }

    func addAttachmentToAgent(
        _ attachment: AgentAttachment,
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID? = nil
    ) {
        addAttachmentsToAgent([attachment], workspaceID: workspaceID, preferredPaneID: preferredPaneID)
    }

    func addAttachmentsToAgent(
        _ attachments: [AgentAttachment],
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID? = nil
    ) {
        guard !attachments.isEmpty else { return }
        if let sessionRuntime = targetAgentSession(
            workspaceID: workspaceID,
            preferredPaneID: preferredPaneID
        ) {
            configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
            sessionRuntime.addAttachments(attachments)
            openAgentTab(
                workspaceID: workspaceID,
                sessionID: sessionRuntime.sessionID,
                preferredPaneID: preferredPaneID
            )
            return
        }

        if let configuredHarness = appSettings.agent.defaultHarness,
           let kind = agentKind(forHarness: configuredHarness) {
            openAgentSession(
                kind,
                workspaceID: workspaceID,
                initialAttachments: attachments,
                preferredPaneID: preferredPaneID
            )
            return
        }

        agentLaunchRequest = AgentLaunchPresentationRequest(
            workspaceID: workspaceID,
            initialAttachments: attachments,
            preferredPaneID: preferredPaneID,
            pendingSessionID: nil,
            pendingTabID: nil
        )
    }

    func openAgentSession(
        _ kind: ACPAgentKind,
        workspaceID: Workspace.ID,
        initialAttachments: [AgentAttachment] = [],
        preferredPaneID: PaneID? = nil
    ) {
        guard let prepared = preparePendingAgentSessionLaunch(
            workspaceID: workspaceID,
            preferredPaneID: preferredPaneID,
            initialAttachments: initialAttachments,
            preferredKind: kind
        ) else {
            return
        }

        selectTab(prepared.tabID)
        launchPreparedAgentSession(
            kind,
            workspaceID: workspaceID,
            sessionID: prepared.runtime.sessionID
        )
    }

    // swiftlint:disable:next function_body_length
    func restoreAgentSession(
        _ record: PersistedAgentSessionRecord,
        workspaceID: Workspace.ID
    ) {
        guard let runtime = runtimeRegistry.runtimeHandle(for: workspaceID) else { return }

        let descriptor = ACPAgentDescriptor.descriptor(for: record.kind)
        let sessionID = AgentSessionID(rawValue: record.sessionID)
        let sessionRuntime = runtime
            .shellState
            .agentRuntimeRegistry
            .ensureSession(
                workspaceID: workspaceID,
                sessionID: sessionID,
                descriptor: descriptor
            )

        guard sessionRuntime.connection == nil,
              sessionRuntime.launchState != .launching else {
            return
        }

        configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
        sessionRuntime.prepareForRestore(
            title: record.title ?? descriptor.displayName,
            subtitle: record.subtitle
        )
        syncTabMetadataFromSessions()

        Task { @MainActor in
            let launchOptions = container.defaultAgentAdapterLaunchOptions(
                currentDirectoryURL: runtime.worktree.workingDirectory
            )

            do {
                let launched = try await container.agentAdapterLauncher.launch(
                    kind: record.kind,
                    options: launchOptions
                )
                guard launched.initializeResult.capabilities.loadSession else {
                    await launched.connection.shutdown()
                    sessionRuntime.recordLaunchFailure(
                        "This adapter does not support session restore. Start a new session instead."
                    )
                    syncTabMetadataFromSessions()
                    return
                }

                let sessionResponse: AgentSessionLoadResponse = try await launched.connection.sendRequest(
                    method: "session/load",
                    params: AgentSessionLoadRequest(
                        sessionId: sessionID,
                        cwd: runtime.worktree.workingDirectory.path
                    ),
                    as: AgentSessionLoadResponse.self
                )

                guard sessionResponse.sessionId == sessionID else {
                    await launched.connection.shutdown()
                    sessionRuntime.recordLaunchFailure(
                        "Restored session identity mismatch. Start a new session instead."
                    )
                    syncTabMetadataFromSessions()
                    return
                }

                sessionRuntime.bind(
                    connection: launched.connection,
                    initializeResult: launched.initializeResult,
                    loadSessionResponse: sessionResponse
                )
                sessionRuntime.updatePresentation(
                    title: record.title ?? launched.descriptor.displayName,
                    subtitle: "Restored"
                )
                syncTabMetadataFromSessions()
            } catch {
                let message = ACPErrorFormatting.describe(error)
                sessionRuntime.recordLaunchFailure(
                    "Failed to restore session: \(message)"
                )
                syncTabMetadataFromSessions()
            }
        }
    }

    func focusAgentSession(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        preferredPaneID: PaneID? = nil
    ) {
        openAgentTab(
            workspaceID: workspaceID,
            sessionID: sessionID,
            preferredPaneID: preferredPaneID
        )
    }

    func openAgentLocationTarget(
        workspaceID: Workspace.ID,
        target: AgentFollowTarget,
        prefersPreview: Bool
    ) {
        if let diff = target.diff,
           openAgentDiffArtifact(
                workspaceID: workspaceID,
                diff: diff,
                prefersPreview: prefersPreview,
                fallbackToEditor: false
           ) {
            return
        }

        guard let fileURL = agentFileURL(
            for: target.location.path,
            workspaceID: workspaceID
        ) else {
            return
        }

        Task { @MainActor in
            await runtimeRegistry
                .runtimeHandle(for: workspaceID)?
                .fileTreeModel?
                .revealURL(fileURL)
        }

        let content = TabContent.editor(workspaceID: workspaceID, url: fileURL)
        if prefersPreview {
            openInPreviewTab(content: content)
        } else {
            openInPermanentTab(content: content)
        }
    }

    @discardableResult
    func openAgentDiffArtifact(
        workspaceID: Workspace.ID,
        diff: AgentDiffContent,
        prefersPreview: Bool,
        fallbackToEditor: Bool = true
    ) -> Bool {
        let allChanges: [GitFileChange] = runtimeRegistry
            .runtimeHandle(for: workspaceID)?
            .gitStore?
            .allChanges
            ?? []
        var matchingChange: GitFileChange?
        for change in allChanges where change.path == diff.path {
            matchingChange = change
            break
        }
        if let change = matchingChange {
            let content = TabContent.gitDiff(
                workspaceID: workspaceID,
                path: change.path,
                isStaged: change.isStaged
            )
            if prefersPreview {
                openInPreviewTab(content: content)
            } else {
                openInPermanentTab(content: content)
            }
            return true
        }

        guard fallbackToEditor,
              let fileURL = agentFileURL(for: diff.path, workspaceID: workspaceID) else {
            return false
        }

        let content = TabContent.editor(workspaceID: workspaceID, url: fileURL)
        if prefersPreview {
            openInPreviewTab(content: content)
        } else {
            openInPermanentTab(content: content)
        }
        return true
    }

    func agentKind(forHarness rawValue: String) -> ACPAgentKind? {
        switch rawValue {
        case AgentSettings.Harness.codex.rawValue:
            .codex
        case AgentSettings.Harness.claudeCode.rawValue:
            .claude
        default:
            nil
        }
    }

    private func targetAgentSession(
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?
    ) -> AgentSessionRuntime? {
        if let preferredPaneID,
           let selectedTab = controller.selectedTab(inPane: preferredPaneID),
           case .agentSession(let selectedWorkspaceID, let sessionID)? = tabContents[selectedTab.id],
           selectedWorkspaceID == workspaceID {
            return runtimeRegistry.runtimeHandle(for: workspaceID)?.agentRuntimeRegistry.session(id: sessionID)
        }

        if let selectedTabId,
           case .agentSession(let selectedWorkspaceID, let sessionID)? = tabContents[selectedTabId],
           selectedWorkspaceID == workspaceID {
            return runtimeRegistry.runtimeHandle(for: workspaceID)?.agentRuntimeRegistry.session(id: sessionID)
        }

        return runtimeRegistry.runtimeHandle(for: workspaceID)?.agentRuntimeRegistry.allSessions.first
    }

    func preparePendingAgentSessionLaunch(
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?,
        initialAttachments: [AgentAttachment],
        preferredKind: ACPAgentKind?
    ) -> (runtime: AgentSessionRuntime, tabID: TabID)? {
        guard let runtime = runtimeRegistry.runtimeHandle(for: workspaceID) else { return nil }

        let descriptor: ACPAgentDescriptor
        if let preferredKind {
            descriptor = ACPAgentDescriptor.descriptor(for: preferredKind)
        } else {
            descriptor = ACPAgentDescriptor(
                kind: .codex,
                displayName: "Agents",
                executableName: "pending-agent"
            )
        }

        let pendingSessionID = AgentSessionID(rawValue: "pending-\(UUID().uuidString)")
        let sessionRuntime = runtime
            .shellState
            .agentRuntimeRegistry
            .ensureSession(
                workspaceID: workspaceID,
                sessionID: pendingSessionID,
                descriptor: descriptor
            )
        sessionRuntime.launchState = .launching
        sessionRuntime.updatePresentation(
            title: preferredKind?.displayName ?? "Agents",
            icon: preferredKind.map(agentIcon(for:)) ?? "message",
            subtitle: preferredKind == nil ? "Choose an agent" : "Launching"
        )
        configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
        sessionRuntime.addAttachments(initialAttachments)

        guard let tabID = openAgentTab(
            workspaceID: workspaceID,
            sessionID: pendingSessionID,
            preferredPaneID: preferredPaneID
        ) else {
            runtime.shellState.agentRuntimeRegistry.removeSession(id: pendingSessionID)
            return nil
        }

        syncTabMetadataFromSessions()
        return (sessionRuntime, tabID)
    }

    func launchPreparedAgentSession(
        _ kind: ACPAgentKind,
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID
    ) {
        guard let runtime = runtimeRegistry.runtimeHandle(for: workspaceID),
              let sessionRuntime = runtime.shellState.agentRuntimeRegistry.session(id: sessionID) else {
            return
        }

        Task { @MainActor in
            let launchOptions = container.defaultAgentAdapterLaunchOptions(
                currentDirectoryURL: runtime.worktree.workingDirectory
            )

            do {
                let launched = try await container.agentAdapterLauncher.launch(
                    kind: kind,
                    options: launchOptions
                )
                let sessionResponse: AgentSessionNewResponse = try await launched.connection.sendRequest(
                    method: "session/new",
                    params: AgentSessionNewRequest(cwd: runtime.worktree.workingDirectory.path),
                    as: AgentSessionNewResponse.self
                )

                let previousSessionID = sessionRuntime.sessionID
                runtime.shellState.agentRuntimeRegistry.rekeySession(
                    sessionRuntime,
                    to: sessionResponse.sessionId,
                    descriptor: launched.descriptor
                )
                migratePreparedAgentSessionReferences(
                    workspaceID: workspaceID,
                    from: previousSessionID,
                    to: sessionResponse.sessionId
                )
                configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
                sessionRuntime.bind(
                    connection: launched.connection,
                    initializeResult: launched.initializeResult,
                    newSessionResponse: sessionResponse
                )
                sessionRuntime.updatePresentation(
                    title: launched.descriptor.displayName,
                    subtitle: "Connected"
                )
                syncTabMetadataFromSessions()
            } catch {
                let message = ACPErrorFormatting.describe(error)
                sessionRuntime.recordLaunchFailure(message)
                syncTabMetadataFromSessions()
                showLauncherUnavailableAlert(
                    title: "Agents Unavailable",
                    message: message
                )
            }
        }
    }

    func cancelPreparedAgentSessionLaunch(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        tabID: TabID
    ) {
        controller.closeTab(tabID)
        runtimeRegistry
            .runtimeHandle(for: workspaceID)?
            .agentRuntimeRegistry
            .removeSession(id: sessionID)
    }

    private func migratePreparedAgentSessionReferences(
        workspaceID: Workspace.ID,
        from previousSessionID: AgentSessionID,
        to sessionID: AgentSessionID
    ) {
        for (tabID, content) in tabContents {
            guard case .agentSession(let tabWorkspaceID, let existingSessionID) = content,
                  tabWorkspaceID == workspaceID,
                  existingSessionID == previousSessionID else {
                continue
            }
            tabContents[tabID] = .agentSession(workspaceID: workspaceID, sessionID: sessionID)
            let presentation = currentTabPresentation(
                for: .agentSession(workspaceID: workspaceID, sessionID: sessionID),
                tabId: tabID
            )
            tabPresentationById[tabID] = presentation
        }
    }

    private func agentIcon(for kind: ACPAgentKind) -> String {
        switch kind {
        case .codex:
            "chevron.left.forwardslash.chevron.right"
        case .claude:
            "brain"
        }
    }

    @discardableResult
    private func openAgentTab(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        preferredPaneID: PaneID? = nil
    ) -> TabID? {
        let content = TabContent.agentSession(
            workspaceID: workspaceID,
            sessionID: sessionID
        )

        if let existingTabID = findExistingTab(for: content) {
            selectTab(existingTabID)
            return existingTabID
        }

        if let preferredPaneID {
            return createTab(in: preferredPaneID, content: content)
        }

        openInPermanentTab(content: content)
        return findExistingTab(for: content)
    }

    private func configureWorkspaceBridgeIfNeeded(
        for sessionRuntime: AgentSessionRuntime,
        workspaceID: Workspace.ID
    ) {
        guard let runtime = runtimeRegistry.runtimeHandle(for: workspaceID) else { return }
        sessionRuntime.configureWorkspaceBridge(
            makeWorkspaceBridge(for: runtime.worktree, shellState: runtime.shellState)
        )
    }

    private func makeWorkspaceBridge(
        for worktree: Worktree,
        shellState: WorkspaceShellState
    ) -> AgentWorkspaceBridge {
        let gitStoreProvider: @MainActor @Sendable () -> GitStore? = {
            shellState.gitStore
        }
        return AgentWorkspaceBridge(
            workspaceID: worktree.id,
            workingDirectoryURL: worktree.workingDirectory,
            editorSessionPool: shellState.editorSessionPool,
            workspaceTerminalRegistry: workspaceTerminalRegistry,
            persistentTerminalHostController: persistentTerminalHostController,
            gitStoreProvider: gitStoreProvider
        )
    }

    private func agentFileURL(
        for path: String,
        workspaceID: Workspace.ID
    ) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let worktree = runtimeRegistry.runtimeHandle(for: workspaceID)?.worktree else {
            return nil
        }
        return worktree.workingDirectory.appendingPathComponent(path)
    }
}
