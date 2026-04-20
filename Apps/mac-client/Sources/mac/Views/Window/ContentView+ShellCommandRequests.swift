// ContentView+ShellCommandRequests.swift
// Reducer-owned shell request execution and external attention ingress.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Editor
import SwiftUI

@MainActor
extension ContentView {
    func applyShellCommandRequestModifiers<V: View>(_ view: V) -> some View {
        applyRunProfileRequestModifiers(
            applyWorkspaceScopedRequestModifiers(
                applyRelaunchRequestModifiers(
                    applySelectionRequestModifiers(
                        applyBasicShellCommandRequestModifiers(view)
                    )
                )
            )
        )
    }

    private func applyBasicShellCommandRequestModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: store.openRepositoryRequestID) { _, requestID in
                guard requestID != nil else { return }
                store.send(.setOpenRepositoryRequestID(nil))
                requestOpenRepository()
            }
            .onChange(of: store.editorCommandRequest) { _, request in
                guard let request else { return }
                store.send(.setEditorCommandRequest(nil))
                executeEditorCommand(request.command)
            }
            .onChange(of: store.saveDefaultLayoutRequestID) { _, requestID in
                guard requestID != nil else { return }
                store.send(.setSaveDefaultLayoutRequestID(nil))
                saveDefaultLayout()
            }
    }

    private func applySelectionRequestModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: store.workspaceTransitionRequest) { _, request in
                guard let request else { return }
                store.send(.setWorkspaceTransitionRequest(nil))
                Task { @MainActor in
                    await executeWorkspaceTransition(request)
                }
            }
            .onChange(of: store.remoteWorkspaceTransitionRequest) { _, request in
                guard let request else { return }
                store.send(.setRemoteWorkspaceTransitionRequest(nil))
                executeRemoteWorkspaceTransition(request)
            }
            .onChange(of: store.workspaceDiscardRequest) { _, request in
                guard let request else { return }
                store.send(.setWorkspaceDiscardRequest(nil))
                Task { @MainActor in
                    await executeWorkspaceDiscard(request)
                }
            }
            .onChange(of: store.initializeRepositoryRequest) { _, request in
                guard let request else { return }
                store.send(.setInitializeRepositoryRequest(nil))
                Task { @MainActor in
                    await initializeRepository(request.repositoryID)
                }
            }
    }

    private func applyWorkspaceScopedRequestModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: store.chatSessionLaunchRequest) { _, request in
                guard let request else { return }
                store.send(.setChatSessionLaunchRequest(nil))
                openChatSession(
                    request.kind,
                    workspaceID: request.workspaceID,
                    initialAttachments: request.initialAttachments,
                    preferredPaneID: request.preferredPaneID
                )
            }
            .onChange(of: store.workspaceCommandRequest) { _, request in
                guard let request else { return }
                store.send(.setWorkspaceCommandRequest(nil))
                executeWorkspaceCommand(request.command)
            }
            .onChange(of: store.focusChatSessionRequest) { _, request in
                guard let request else { return }
                store.send(.setFocusChatSessionRequest(nil))
                focusChatSession(workspaceID: request.workspaceID, sessionID: request.sessionID)
            }
            .onChange(of: store.remoteTerminalLaunchRequest) { _, request in
                guard let request else { return }
                store.send(.setRemoteTerminalLaunchRequest(nil))
                Task { @MainActor in
                    await executeRemoteTerminalLaunch(request)
                }
            }
    }

    private func applyRunProfileRequestModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: store.runProfileLaunchRequest) { _, request in
                guard let request else { return }
                store.send(.setRunProfileLaunchRequest(nil))
                Task { @MainActor in
                    await executeRunProfileLaunch(request)
                }
            }
            .onChange(of: store.runProfileStopRequest) { _, request in
                guard let request else { return }
                store.send(.setRunProfileStopRequest(nil))
                Task { @MainActor in
                    await executeRunProfileStop(request)
                }
            }
    }

    private func applyRelaunchRequestModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: store.windowRelaunchRestoreRequest) { _, request in
                guard let request else { return }
                store.send(.setWindowRelaunchRestoreRequest(nil))
                Task { @MainActor in
                    await executeWindowRelaunchRestore(request)
                }
            }
    }

    private func executeEditorCommand(_ command: WindowFeature.EditorCommand) {
        switch command {
        case .find:
            showFindInActiveEditor()
        case .save:
            saveActiveEditor()
        case .saveAs:
            saveActiveEditorAs()
        case .saveAll:
            Task { @MainActor in
                _ = await editorSessionRegistry.saveAll()
            }
        }
    }

    private func executeWorkspaceCommand(_ command: WindowFeature.WorkspaceCommand) {
        switch command {
        case .openChat:
            openDefaultOrPromptChatForSelectedWorkspace()
        case .launchShell:
            openShellForSelectedWorkspace()
        case .launchClaude:
            launchClaudeForSelectedWorkspace()
        case .launchCodex:
            launchCodexForSelectedWorkspace()
        case .jumpToLatestUnreadWorkspace:
            Task { @MainActor in
                await jumpToLatestUnreadWorkspace()
            }
        case .runWorkspaceProfile:
            break
        }
    }

    func executeWorkspaceTransition(
        _ request: WindowFeature.WorkspaceTransitionRequest
    ) async {
        if request.requiresRepositoryConfirmation {
            guard await confirmCloseCurrentRepository() else { return }
        }

        if request.shouldPersistVisibleWorkspaceState {
            persistVisibleWorkspaceState()
        }
        if request.shouldResetHostWorkspaceState {
            resetWorkspaceState()
        }

        switch request.catalogRefreshStrategy {
        case .none:
            applyWorkspaceTransitionSelection(request)
        case .retryIfSelectionMissing:
            store.send(.selectRepository(request.targetRepositoryID))
        case .blockingTargetWorkspace:
            applyWorkspaceTransitionSelection(request)
            await refreshRepositoryCatalog(repositoryID: request.targetRepositoryID)
            if let workspaceID = request.targetWorkspaceID {
                store.send(.selectWorkspace(workspaceID))
            }
        }

        guard let selectedWorktree = restoreSelectedWorkspaceOrReset() else {
            guard request.catalogRefreshStrategy == .retryIfSelectionMissing else { return }
            await refreshRepositoryCatalog(repositoryID: request.targetRepositoryID)
            _ = restoreSelectedWorkspaceOrReset()
            return
        }

        if request.shouldScheduleDeferredRefresh {
            scheduleDeferredRepositoryRefresh(
                repositoryID: request.targetRepositoryID,
                workspaceID: selectedWorktree.id,
                reason: "workspace-transition"
            )
        }
    }

    private func applyWorkspaceTransitionSelection(
        _ request: WindowFeature.WorkspaceTransitionRequest
    ) {
        if request.sourceRepositoryID != request.targetRepositoryID {
            store.send(.selectRepository(request.targetRepositoryID))
        }
        if let workspaceID = request.targetWorkspaceID {
            store.send(.selectWorkspace(workspaceID))
        }
    }

    private func executeWorkspaceDiscard(
        _ request: WindowFeature.WorkspaceDiscardRequest
    ) async {
        discardWorkspaceState(request.workspaceID)
        store.send(.removeWorkspaceState(request.workspaceID, repositoryID: request.repositoryID))
        await refreshRepositoryCatalog(repositoryID: request.repositoryID)
        if selectedRepositoryID == request.repositoryID {
            _ = restoreSelectedWorkspaceOrReset()
        }
    }

    private func executeRemoteWorkspaceTransition(
        _ request: WindowFeature.RemoteWorkspaceTransitionRequest
    ) {
        if request.shouldPersistVisibleWorkspaceState {
            persistVisibleWorkspaceState()
        }
        if request.shouldResetHostWorkspaceState {
            resetVisibleWorkspaceRuntime()
        }

        store.send(
            .selectRemoteWorktree(
                repositoryID: request.targetRepositoryID,
                workspaceID: request.targetWorkspaceID
            )
        )
        ensureWorkspaceLayout(for: request.targetWorkspaceID)
        renderWorkspaceLayout(for: request.targetWorkspaceID)
    }
}
