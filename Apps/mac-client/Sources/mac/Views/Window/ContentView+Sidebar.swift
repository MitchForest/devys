// ContentView+Sidebar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Git

extension ContentView {
    var navigatorSurface: some View {
        ContentViewNavigatorSurface(
            workspaceCatalog: workspaceCatalog,
            runtimeRegistry: runtimeRegistry,
            workspaceAttentionStore: workspaceAttentionStore,
            navigatorRevealRequest: navigatorRevealRequest,
            onAddRepository: { requestOpenRepository() },
            onMoveRepository: { repositoryID, offset in
                moveRepository(repositoryID, by: offset)
            },
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
            onSelectRepository: { repositoryID in
                Task { @MainActor in
                    await selectRepository(repositoryID)
                }
            },
            onSelectWorkspace: { repositoryID, workspaceID in
                Task { @MainActor in
                    await selectWorkspace(workspaceID, in: repositoryID)
                }
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
            }
        )
    }

    @ViewBuilder
    var sidebarContent: some View {
        ContentViewSidebarSurface(
            workspaceCatalog: workspaceCatalog,
            runtimeRegistry: runtimeRegistry,
            repositorySettingsStore: repositorySettingsStore,
            onPreviewFile: { workspaceID, url in
                openInPreviewTab(content: .editor(workspaceID: workspaceID, url: url))
            },
            onOpenFile: { workspaceID, url in
                openInPermanentTab(content: .editor(workspaceID: workspaceID, url: url))
            },
            onAddFileToAgent: { workspaceID, url in
                addAttachmentToAgent(.file(url: url), workspaceID: workspaceID)
            },
            onOpenDiff: { workspaceID, path, isStaged, permanent in
                let content = TabContent.gitDiff(
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
                   let context = workspaceCatalog.workspaceContext(for: workspaceID) {
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
            onOpenPort: openPort,
            onCopyPortURL: copyPortURL,
            onStopPortProcess: stopPortProcess
        )
    }
}
