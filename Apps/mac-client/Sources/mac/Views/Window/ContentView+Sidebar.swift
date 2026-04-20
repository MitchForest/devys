// ContentView+Sidebar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Git
import RemoteCore
import SwiftUI
import UI
import Workspace

extension ContentView {
    var repoRailSurface: some View {
        let infoEntries = workspaceOperationalState.metadataEntriesByWorkspaceID
        let attentionSummaries = workspaceOperationalState.attentionSummariesByWorkspace
        let remoteStatusHints = Dictionary(
            uniqueKeysWithValues: store.remoteWorktreesByRepository.values
                .flatMap { $0 }
                .compactMap { worktree in
                    worktree.status.isDirty ? (worktree.id, StatusHint.dirty) : nil
                }
        )

        return ContentViewRepoRailSurface(
            repositories: store.repositories,
            remoteRepositories: store.remoteRepositories,
            selectedRepositoryID: selectedRepositoryID,
            selectedRemoteRepositoryID: store.selectedRemoteRepositoryID,
            selectedWorkspaceID: selectedWorkspaceID,
            worktreesByRepository: store.worktreesByRepository,
            remoteWorktreesByRepository: store.remoteWorktreesByRepository,
            workspaceStatesByID: store.workspaceStatesByID,
            worktreeStatusHints: computeWorktreeStatusHints(
                worktreesByRepository: store.worktreesByRepository,
                infoEntries: infoEntries,
                attentionSummaries: attentionSummaries
            ),
            remoteWorktreeStatusHints: remoteStatusHints,
            onAddRepository: { store.send(.requestAddRepository) },
            onRemoveRepository: { repositoryID in
                Task { @MainActor in
                    await removeRepository(repositoryID)
                }
            },
            onRemoveRemoteRepository: { repositoryID in
                store.send(.removeRemoteRepository(repositoryID))
            },
            onInitializeRepository: { repositoryID in
                Task { @MainActor in
                    await initializeRepository(repositoryID)
                }
            },
            onCreateWorkspace: { repositoryID in
                presentWorkspaceCreation(for: repositoryID)
            },
            onCreateRemoteWorktree: { repositoryID in
                presentRemoteWorktreeCreation(for: repositoryID)
            },
            onSelectWorkspace: { repositoryID, workspaceID in
                Task { @MainActor in
                    await selectWorkspace(workspaceID, in: repositoryID)
                }
            },
            onSelectRemoteWorktree: { repositoryID, workspaceID in
                store.send(
                    .requestRemoteWorktreeSelection(
                        repositoryID: repositoryID,
                        workspaceID: workspaceID
                    )
                )
            },
            onReorderRepository: { repositoryID, toIndex in
                store.send(.reorderRepository(repositoryID, toIndex: toIndex))
            },
            onSetWorkspacePinned: { repositoryID, workspaceID, isPinned in
                setWorkspacePinned(workspaceID, in: repositoryID, isPinned: isPinned)
            },
            onSetWorkspaceArchived: { repositoryID, workspaceID, isArchived in
                setWorkspaceArchived(workspaceID, in: repositoryID, isArchived: isArchived)
            },
            onRenameWorkspace: { repositoryID, workspaceID in
                renameWorkspace(workspaceID, in: repositoryID)
            },
            onDeleteWorkspace: { repositoryID, workspaceID in
                Task { @MainActor in
                    await deleteWorkspace(workspaceID, in: repositoryID)
                }
            },
            onRevealWorkspaceInFinder: { repositoryID, workspaceID in
                revealWorkspaceInFinder(workspaceID, in: repositoryID)
            },
            onOpenWorkspaceInExternalEditor: { repositoryID, workspaceID in
                openWorkspaceInExternalEditor(workspaceID, in: repositoryID)
            },
            onRevealRepositoryInFinder: { repositoryID in
                guard let repo = store.repositories.first(where: { $0.id == repositoryID }) else {
                    return
                }
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.rootURL.path)
            },
            onRefreshRemoteRepository: { repositoryID in
                store.send(.refreshRemoteRepository(repositoryID))
            },
            onFetchRemoteRepository: { repositoryID in
                store.send(.fetchRemoteRepository(repositoryID))
            },
            onPullRemoteWorktree: { repositoryID, workspaceID in
                store.send(.pullRemoteWorktree(repositoryID: repositoryID, workspaceID: workspaceID))
            },
            onPushRemoteWorktree: { repositoryID, workspaceID in
                store.send(.pushRemoteWorktree(repositoryID: repositoryID, workspaceID: workspaceID))
            }
        )
    }

    @ViewBuilder
    var sidebarContent: some View {
        if isRemoteWorkspaceSelected {
            RemoteWorkspaceSidebarView(
                activeSidebar: activeSidebarItem ?? .files,
                repository: selectedRemoteRepository,
                worktree: selectedRemoteWorktree,
                onRefresh: {
                    guard let repositoryID = selectedRemoteRepository?.id else { return }
                    store.send(.refreshRemoteRepository(repositoryID))
                },
                onFetch: {
                    guard let repositoryID = selectedRemoteRepository?.id else { return }
                    store.send(.fetchRemoteRepository(repositoryID))
                },
                onPull: {
                    guard let repositoryID = selectedRemoteRepository?.id,
                          let worktreeID = selectedRemoteWorktree?.id else { return }
                    store.send(.pullRemoteWorktree(repositoryID: repositoryID, workspaceID: worktreeID))
                },
                onPush: {
                    guard let repositoryID = selectedRemoteRepository?.id,
                          let worktreeID = selectedRemoteWorktree?.id else { return }
                    store.send(.pushRemoteWorktree(repositoryID: repositoryID, workspaceID: worktreeID))
                },
                onCreateWorktree: {
                    guard let repositoryID = selectedRemoteRepository?.id else { return }
                    presentRemoteWorktreeCreation(for: repositoryID)
                },
                onOpenShell: { openShellForSelectedWorkspace() }
            )
        } else {
            let sidebarWorkspaceID = selectedWorkspaceID
            let currentWorktree = selectedCatalogWorktree
            let selectedWorkspaceInfo = selectedWorkspaceID.flatMap {
                workspaceOperationalState.metadataEntriesByWorkspaceID[$0]
            }
            let changeSummary = selectedWorkspaceInfo?.statusSummary
            let changeCount = (changeSummary?.staged ?? 0)
                + (changeSummary?.unstaged ?? 0)
                + (changeSummary?.untracked ?? 0)
                + (changeSummary?.conflicts ?? 0)

            ContentViewSidebarSurface(
                activeSidebar: activeSidebarItem ?? .files,
                currentWorktree: currentWorktree,
                selectedWorkspaceID: sidebarWorkspaceID,
                fileTreeModel: sidebarWorkspaceID.flatMap(runtimeRegistry.fileTreeModel(for:)),
                gitStatusIndex: sidebarWorkspaceID.flatMap(runtimeRegistry.gitStatusIndex(for:)),
                gitStore: sidebarWorkspaceID.flatMap(runtimeRegistry.gitStore(for:)),
                changeCount: changeCount,
                chatSessions: hostedChatSessions,
                workflowState: sidebarWorkspaceID.map { workflowWorkspaceState(for: $0) }
                    ?? WindowFeature.WorkflowWorkspaceState(),
                portsByWorkspaceID: workspaceOperationalState.portsByWorkspaceID,
                repositorySettingsStore: repositorySettingsStore,
                onSelectSidebar: showSidebarItem,
                onPreviewFile: { workspaceID, url in
                    openInPreviewTab(content: .editor(workspaceID: workspaceID, url: url))
                },
                onOpenFile: { workspaceID, url in
                    openInPermanentTab(content: .editor(workspaceID: workspaceID, url: url))
                },
                onAddFileToChat: { workspaceID, url in
                    addAttachmentToChat(.file(url: url), workspaceID: workspaceID)
                },
                onRenameFile: { workspaceID, url in
                    renameFileTreeItem(url, in: workspaceID)
                },
                onDeleteFiles: { workspaceID, urls in
                    Task { @MainActor in
                        await deleteFileTreeItems(urls, in: workspaceID)
                    }
                },
                onOpenDiff: { workspaceID, path, isStaged, permanent in
                    let content = WorkspaceTabContent.gitDiff(
                        workspaceID: workspaceID,
                        path: path,
                        isStaged: isStaged
                    )

                    if permanent {
                        openInPermanentTab(content: content)
                    } else {
                        openInPreviewTab(content: content)
                    }
                },
                onAddDiffToChat: { workspaceID, path, isStaged in
                    addAttachmentToChat(.gitDiff(path: path, isStaged: isStaged), workspaceID: workspaceID)
                },
                onCreateChatSession: { workspaceID in
                    if visibleWorkspaceID != workspaceID,
                       let context = windowWorkspaceContext(for: workspaceID) {
                        Task { @MainActor in
                            await selectWorkspace(workspaceID, in: context.repository.id)
                            openDefaultOrPromptChatForSelectedWorkspace()
                        }
                    } else {
                        openDefaultOrPromptChatForSelectedWorkspace()
                    }
                },
                onOpenChatSession: { workspaceID, sessionID in
                    focusChatSession(workspaceID: workspaceID, sessionID: sessionID)
                },
                onCreateWorkflowDefinition: createWorkflowDefinition,
                onOpenWorkflowDefinition: openWorkflowDefinition,
                onStartWorkflowDefinition: startWorkflowRun,
                onDeleteWorkflowDefinition: deleteWorkflowDefinition,
                onOpenWorkflowRun: { workspaceID, runID in
                    openInPermanentTab(content: .workflowRun(workspaceID: workspaceID, runID: runID))
                },
                onDeleteWorkflowRun: deleteWorkflowRun,
                onOpenPort: openPort,
                onCopyPortURL: copyPortURL,
                onStopPortProcess: stopPortProcess
            )
        }
    }
}
