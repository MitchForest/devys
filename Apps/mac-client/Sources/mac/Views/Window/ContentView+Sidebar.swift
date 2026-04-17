// ContentView+Sidebar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import SwiftUI
import Git
import UI
import Workspace

extension ContentView {
    var repoRailSurface: some View {
        let infoEntries = workspaceOperationalState.metadataEntriesByWorkspaceID
        let attentionSummaries = workspaceOperationalState.attentionSummariesByWorkspace

        return ContentViewRepoRailSurface(
            repositories: store.repositories,
            selectedRepositoryID: selectedRepositoryID,
            selectedWorkspaceID: selectedWorkspaceID,
            worktreesByRepository: store.worktreesByRepository,
            workspaceStatesByID: store.workspaceStatesByID,
            worktreeStatusHints: computeWorktreeStatusHints(
                worktreesByRepository: store.worktreesByRepository,
                infoEntries: infoEntries,
                attentionSummaries: attentionSummaries
            ),
            onAddRepository: { requestOpenRepository() },
            onRemoveRepository: { repositoryID in
                Task { @MainActor in
                    await removeRepository(repositoryID)
                }
            },
            onInitializeRepository: { repositoryID in
                Task { @MainActor in
                    await initializeRepository(repositoryID)
                }
            },
            onCreateWorkspace: { repositoryID in
                presentWorkspaceCreation(for: repositoryID)
            },
            onSelectWorkspace: { repositoryID, workspaceID in
                Task { @MainActor in
                    await selectWorkspace(workspaceID, in: repositoryID)
                }
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
            }
        )
    }

    @ViewBuilder
    var sidebarContent: some View {
        let activeWorkspaceID = visibleWorkspaceID
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
            selectedRepositoryRootURL: selectedRepositoryRootURL,
            currentWorktree: activeWorkspaceID.flatMap(runtimeRegistry.worktree(for:)),
            selectedWorkspaceID: activeWorkspaceID,
            fileTreeModel: activeWorkspaceID.flatMap(runtimeRegistry.fileTreeModel(for:)),
            gitStatusIndex: activeWorkspaceID.flatMap(runtimeRegistry.gitStatusIndex(for:)),
            gitStore: activeWorkspaceID.flatMap(runtimeRegistry.gitStore(for:)),
            changeCount: changeCount,
            agentSessions: hostedAgentSessions,
            workflowState: activeWorkspaceID.map { workflowWorkspaceState(for: $0) }
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
            onAddFileToAgent: { workspaceID, url in
                addAttachmentToAgent(.file(url: url), workspaceID: workspaceID)
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
            onAddDiffToAgent: { workspaceID, path, isStaged in
                addAttachmentToAgent(.gitDiff(path: path, isStaged: isStaged), workspaceID: workspaceID)
            },
            onCreateAgentSession: { workspaceID in
                if visibleWorkspaceID != workspaceID,
                   let context = windowWorkspaceContext(for: workspaceID) {
                    Task { @MainActor in
                        await selectWorkspace(workspaceID, in: context.repository.id)
                        openDefaultOrPromptAgentForSelectedWorkspace()
                    }
                } else {
                    openDefaultOrPromptAgentForSelectedWorkspace()
                }
            },
            onOpenAgentSession: { workspaceID, sessionID in
                focusAgentSession(workspaceID: workspaceID, sessionID: sessionID)
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
