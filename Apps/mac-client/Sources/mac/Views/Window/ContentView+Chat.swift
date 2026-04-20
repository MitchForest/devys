import ACPClientKit
import AppFeatures
import Foundation
import Git
import Split
import UI
import Workspace

@MainActor
extension ContentView {
    func openDefaultOrPromptChatForSelectedWorkspace(
        initialAttachments: [ChatAttachment] = [],
        preferredPaneID: PaneID? = nil
    ) {
        guard let workspaceID = activeWorktree?.id else { return }
        requestChatSessionLaunch(
            workspaceID: workspaceID,
            initialAttachments: initialAttachments,
            preferredPaneID: preferredPaneID
        )
    }

    func addAttachmentToChat(
        _ attachment: ChatAttachment,
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID? = nil
    ) {
        addAttachmentsToChat([attachment], workspaceID: workspaceID, preferredPaneID: preferredPaneID)
    }

    func addAttachmentsToChat(
        _ attachments: [ChatAttachment],
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID? = nil
    ) {
        guard !attachments.isEmpty else { return }
        if let sessionRuntime = targetChatSession(
            workspaceID: workspaceID,
            preferredPaneID: preferredPaneID
        ) {
            configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
            sessionRuntime.addAttachments(attachments)
            openChatTab(
                workspaceID: workspaceID,
                sessionID: sessionRuntime.sessionID,
                preferredPaneID: preferredPaneID
            )
            return
        }

        requestChatSessionLaunch(
            workspaceID: workspaceID,
            initialAttachments: attachments,
            preferredPaneID: preferredPaneID
        )
    }

    func openChatSession(
        _ kind: ACPAgentKind,
        workspaceID: Workspace.ID,
        initialAttachments: [ChatAttachment] = [],
        preferredPaneID: PaneID? = nil
    ) {
        guard let prepared = preparePendingChatSessionLaunch(
            workspaceID: workspaceID,
            preferredPaneID: preferredPaneID,
            initialAttachments: initialAttachments,
            preferredKind: kind
        ) else {
            return
        }

        selectTab(prepared.tabID)
        launchPreparedChatSession(
            kind,
            workspaceID: workspaceID,
            sessionID: prepared.runtime.sessionID
        )
    }

    // swiftlint:disable:next function_body_length
    func restoreChatSession(
        _ record: PersistedChatSessionRecord,
        workspaceID: Workspace.ID
    ) {
        guard let worktree = runtimeRegistry.worktree(for: workspaceID) else { return }

        let descriptor = ACPAgentDescriptor.descriptor(for: record.kind)
        let sessionID = ChatSessionID(rawValue: record.sessionID)
        guard let sessionRuntime = runtimeRegistry.ensureChatSession(
            in: workspaceID,
            sessionID: sessionID,
            descriptor: descriptor
        ) else {
            return
        }
        hostedContentBridge.attachChatSession(sessionRuntime, workspaceID: workspaceID)

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

    func focusChatSession(
        workspaceID: Workspace.ID,
        sessionID: ChatSessionID,
        preferredPaneID: PaneID? = nil
    ) {
        openChatTab(
            workspaceID: workspaceID,
            sessionID: sessionID,
            preferredPaneID: preferredPaneID
        )
    }

    func openChatLocationTarget(
        workspaceID: Workspace.ID,
        target: AgentFollowTarget,
        prefersPreview: Bool
    ) {
        if let diff = target.diff,
           openChatDiffArtifact(
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
    func openChatDiffArtifact(
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

    func chatProviderKind(forHarness rawValue: String) -> ACPAgentKind? {
        switch rawValue {
        case ChatSettings.Harness.codex.rawValue:
            .codex
        case ChatSettings.Harness.claudeCode.rawValue:
            .claude
        default:
            nil
        }
    }

    func requestChatSessionLaunch(
        workspaceID: Workspace.ID,
        initialAttachments: [ChatAttachment] = [],
        preferredPaneID: PaneID? = nil,
        preferredKind: ACPAgentKind? = nil
    ) {
        store.send(
            .requestChatSessionLaunch(
                WindowFeature.ChatSessionLaunchIntent(
                    workspaceID: workspaceID,
                    initialAttachments: initialAttachments,
                    preferredPaneID: preferredPaneID,
                    preferredKind: preferredKind
                )
            )
        )
    }

    private func targetChatSession(
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?
    ) -> ChatSessionRuntime? {
        if let preferredPaneID,
           let selectedTabID = paneLayout(for: preferredPaneID)?.selectedTabID,
           case .chatSession(let selectedWorkspaceID, let sessionID)? = tabContents[selectedTabID],
           selectedWorkspaceID == workspaceID {
            return runtimeRegistry.chatSession(id: sessionID, in: workspaceID)
        }

        if let selectedTabId,
           case .chatSession(let selectedWorkspaceID, let sessionID)? = tabContents[selectedTabId],
           selectedWorkspaceID == workspaceID {
            return runtimeRegistry.chatSession(id: sessionID, in: workspaceID)
        }

        return runtimeRegistry.allChatSessions(for: workspaceID).first
    }

    func preparePendingChatSessionLaunch(
        workspaceID: Workspace.ID,
        preferredPaneID: PaneID?,
        initialAttachments: [ChatAttachment],
        preferredKind: ACPAgentKind?
    ) -> (runtime: ChatSessionRuntime, tabID: TabID)? {
        guard runtimeRegistry.worktree(for: workspaceID) != nil else { return nil }

        let descriptor: ACPAgentDescriptor
        if let preferredKind {
            descriptor = ACPAgentDescriptor.descriptor(for: preferredKind)
        } else {
            descriptor = ACPAgentDescriptor(
                kind: .codex,
                displayName: "Chat",
                executableName: "pending-chat"
            )
        }

        let pendingSessionID = ChatSessionID(rawValue: "pending-\(UUID().uuidString)")
        guard let sessionRuntime = runtimeRegistry.ensureChatSession(
            in: workspaceID,
            sessionID: pendingSessionID,
            descriptor: descriptor
        ) else {
            return nil
        }
        hostedContentBridge.attachChatSession(sessionRuntime, workspaceID: workspaceID)
        sessionRuntime.launchState = .launching
        sessionRuntime.updatePresentation(
            title: preferredKind?.displayName ?? "Chat",
            icon: preferredKind.map(agentIcon(for:)) ?? "person.crop.circle.badge.plus",
            subtitle: preferredKind == nil ? "Choose a provider" : "Launching"
        )
        configureWorkspaceBridgeIfNeeded(for: sessionRuntime, workspaceID: workspaceID)
        sessionRuntime.addAttachments(initialAttachments)

        guard let tabID = openChatTab(
            workspaceID: workspaceID,
            sessionID: pendingSessionID,
            preferredPaneID: preferredPaneID
        ) else {
            runtimeRegistry.removeChatSession(id: pendingSessionID, in: workspaceID)
            return nil
        }

        syncTabMetadataFromSessions()
        return (sessionRuntime, tabID)
    }

    // swiftlint:disable:next function_body_length
    func launchPreparedChatSession(
        _ kind: ACPAgentKind,
        workspaceID: Workspace.ID,
        sessionID: ChatSessionID
    ) {
        guard let worktree = runtimeRegistry.worktree(for: workspaceID),
              let sessionRuntime = runtimeRegistry.chatSession(id: sessionID, in: workspaceID) else {
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
                runtimeRegistry.rekeyChatSession(
                    sessionRuntime,
                    in: workspaceID,
                    to: sessionResponse.sessionId,
                    descriptor: launched.descriptor
                )
                migratePreparedChatSessionReferences(
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
                    title: "Chat Unavailable",
                    message: message
                )
            }
        }
    }

    func cancelPreparedChatSessionLaunch(
        workspaceID: Workspace.ID,
        sessionID: ChatSessionID,
        tabID: TabID
    ) {
        if let paneID = paneID(for: tabID, workspaceID: workspaceID) {
            closeTab(tabID, in: paneID, workspaceID: workspaceID)
        }
        if let runtime = runtimeRegistry.chatSession(id: sessionID, in: workspaceID) {
            hostedContentBridge.detachChatSession(runtime, workspaceID: workspaceID)
        }
        runtimeRegistry.removeChatSession(id: sessionID, in: workspaceID)
    }

    private func migratePreparedChatSessionReferences(
        workspaceID: Workspace.ID,
        from previousSessionID: ChatSessionID,
        to sessionID: ChatSessionID
    ) {
        for (tabID, content) in tabContents {
            guard case .chatSession(let tabWorkspaceID, let existingSessionID) = content,
                  tabWorkspaceID == workspaceID,
                  existingSessionID == previousSessionID else {
                continue
            }
            let nextContent = WorkspaceTabContent.chatSession(
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
    private func openChatTab(
        workspaceID: Workspace.ID,
        sessionID: ChatSessionID,
        preferredPaneID: PaneID? = nil
    ) -> TabID? {
        let content = WorkspaceTabContent.chatSession(
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
        for sessionRuntime: ChatSessionRuntime,
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
