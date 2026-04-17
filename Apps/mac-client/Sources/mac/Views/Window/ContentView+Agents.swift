import ACPClientKit
import AppFeatures
import Foundation
import Git
import Split
import UI
import Workspace

@MainActor
extension ContentView {
    func openDefaultOrPromptAgentForSelectedWorkspace(
        initialAttachments: [AgentAttachment] = [],
        preferredPaneID: PaneID? = nil
    ) {
        guard let workspaceID = activeWorktree?.id else { return }
        requestAgentSessionLaunch(
            workspaceID: workspaceID,
            initialAttachments: initialAttachments,
            preferredPaneID: preferredPaneID
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

        requestAgentSessionLaunch(
            workspaceID: workspaceID,
            initialAttachments: attachments,
            preferredPaneID: preferredPaneID
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
        guard let worktree = runtimeRegistry.worktree(for: workspaceID) else { return }

        let descriptor = ACPAgentDescriptor.descriptor(for: record.kind)
        let sessionID = AgentSessionID(rawValue: record.sessionID)
        guard let sessionRuntime = runtimeRegistry.ensureAgentSession(
            in: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        ) else {
            return
        }
        hostedContentBridge.attachAgentSession(sessionRuntime, workspaceID: workspaceID)

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
                currentDirectoryURL: worktree.workingDirectory
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
                        cwd: worktree.workingDirectory.path
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
            await runtimeRegistry.fileTreeModel(for: workspaceID)?.revealURL(fileURL)
        }

        let content = WorkspaceTabContent.editor(workspaceID: workspaceID, url: fileURL)
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
        let allChanges: [GitFileChange] = runtimeRegistry.gitStore(for: workspaceID)?.allChanges ?? []
        var matchingChange: GitFileChange?
        for change in allChanges where change.path == diff.path {
            matchingChange = change
            break
        }
        if let change = matchingChange {
            let content = WorkspaceTabContent.gitDiff(
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

        let content = WorkspaceTabContent.editor(workspaceID: workspaceID, url: fileURL)
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

    func requestAgentSessionLaunch(
        workspaceID: Workspace.ID,
        initialAttachments: [AgentAttachment] = [],
        preferredPaneID: PaneID? = nil,
        preferredKind: ACPAgentKind? = nil
    ) {
        store.send(
            .requestAgentSessionLaunch(
                WindowFeature.AgentSessionLaunchIntent(
                    workspaceID: workspaceID,
                    initialAttachments: initialAttachments,
                    preferredPaneID: preferredPaneID,
                    preferredKind: preferredKind
                )
            )
        )
    }

    private func targetAgentSession(
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?
    ) -> AgentSessionRuntime? {
        if let preferredPaneID,
           let selectedTabID = paneLayout(for: preferredPaneID)?.selectedTabID,
           case .agentSession(let selectedWorkspaceID, let sessionID)? = tabContents[selectedTabID],
           selectedWorkspaceID == workspaceID {
            return runtimeRegistry.agentSession(id: sessionID, in: workspaceID)
        }

        if let selectedTabId,
           case .agentSession(let selectedWorkspaceID, let sessionID)? = tabContents[selectedTabId],
           selectedWorkspaceID == workspaceID {
            return runtimeRegistry.agentSession(id: sessionID, in: workspaceID)
        }

        return runtimeRegistry.allAgentSessions(for: workspaceID).first
    }

    func preparePendingAgentSessionLaunch(
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?,
        initialAttachments: [AgentAttachment],
        preferredKind: ACPAgentKind?
    ) -> (runtime: AgentSessionRuntime, tabID: TabID)? {
        guard runtimeRegistry.worktree(for: workspaceID) != nil else { return nil }

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
        guard let sessionRuntime = runtimeRegistry.ensureAgentSession(
            in: workspaceID,
            sessionID: pendingSessionID,
            descriptor: descriptor
        ) else {
            return nil
        }
        hostedContentBridge.attachAgentSession(sessionRuntime, workspaceID: workspaceID)
        sessionRuntime.launchState = .launching
        sessionRuntime.updatePresentation(
            title: preferredKind?.displayName ?? "Agents",
            icon: preferredKind.map(agentIcon(for:)) ?? "person.crop.circle.badge.plus",
            subtitle: preferredKind == nil ? "Choose an agent" : "Launching"
        )
        configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
        sessionRuntime.addAttachments(initialAttachments)

        guard let tabID = openAgentTab(
            workspaceID: workspaceID,
            sessionID: pendingSessionID,
            preferredPaneID: preferredPaneID
        ) else {
            runtimeRegistry.removeAgentSession(id: pendingSessionID, in: workspaceID)
            return nil
        }

        syncTabMetadataFromSessions()
        return (sessionRuntime, tabID)
    }

    // swiftlint:disable:next function_body_length
    func launchPreparedAgentSession(
        _ kind: ACPAgentKind,
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID
    ) {
        guard let worktree = runtimeRegistry.worktree(for: workspaceID),
              let sessionRuntime = runtimeRegistry.agentSession(id: sessionID, in: workspaceID) else {
            return
        }

        Task { @MainActor in
            let launchOptions = container.defaultAgentAdapterLaunchOptions(
                currentDirectoryURL: worktree.workingDirectory
            )

            do {
                let launched = try await container.agentAdapterLauncher.launch(
                    kind: kind,
                    options: launchOptions
                )
                let sessionResponse: AgentSessionNewResponse = try await launched.connection.sendRequest(
                    method: "session/new",
                    params: AgentSessionNewRequest(cwd: worktree.workingDirectory.path),
                    as: AgentSessionNewResponse.self
                )

                let previousSessionID = sessionRuntime.sessionID
                runtimeRegistry.rekeyAgentSession(
                    sessionRuntime,
                    in: workspaceID,
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
        if let paneID = paneID(for: tabID, workspaceID: workspaceID) {
            closeTab(tabID, in: paneID, workspaceID: workspaceID)
        }
        if let runtime = runtimeRegistry.agentSession(id: sessionID, in: workspaceID) {
            hostedContentBridge.detachAgentSession(runtime, workspaceID: workspaceID)
        }
        runtimeRegistry.removeAgentSession(id: sessionID, in: workspaceID)
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
            let nextContent = WorkspaceTabContent.agentSession(
                workspaceID: workspaceID,
                sessionID: sessionID
            )
            setTabContent(nextContent, for: tabID)
            let presentation = currentTabPresentation(
                for: nextContent,
                tabId: tabID
            )
            tabPresentationById[tabID] = presentation
        }
    }

    private func agentIcon(for kind: ACPAgentKind) -> String {
        switch kind {
        case .codex:
            DevysIconName.codex
        case .claude:
            DevysIconName.claudeCode
        }
    }

    @discardableResult
    private func openAgentTab(
        workspaceID: Workspace.ID,
        sessionID: AgentSessionID,
        preferredPaneID: PaneID? = nil
    ) -> TabID? {
        let content = WorkspaceTabContent.agentSession(
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
        guard let bridge = makeWorkspaceBridge(for: workspaceID) else { return }
        sessionRuntime.configureWorkspaceBridge(bridge)
    }

    private func makeWorkspaceBridge(for workspaceID: Workspace.ID) -> AgentWorkspaceBridge? {
        guard let worktree = runtimeRegistry.worktree(for: workspaceID),
              let editorSessionPool = runtimeRegistry.editorSessionPool(for: workspaceID) else {
            return nil
        }
        let gitStoreProvider: @MainActor @Sendable () -> GitStore? = {
            self.runtimeRegistry.gitStore(for: workspaceID)
        }
        return AgentWorkspaceBridge(
            workspaceID: worktree.id,
            workingDirectoryURL: worktree.workingDirectory,
            editorSessionPool: editorSessionPool,
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
        guard let worktree = runtimeRegistry.worktree(for: workspaceID) else {
            return nil
        }
        return worktree.workingDirectory.appendingPathComponent(path)
    }
}
