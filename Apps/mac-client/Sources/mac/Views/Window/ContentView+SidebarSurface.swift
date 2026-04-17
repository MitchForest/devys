import AppFeatures
import Git
import SwiftUI
import UI
import Workspace

@MainActor
struct ContentViewSidebarSurface: View {
    let activeSidebar: WorkspaceSidebarMode
    let selectedRepositoryRootURL: URL?
    let currentWorktree: Worktree?
    let selectedWorkspaceID: Workspace.ID?
    let fileTreeModel: FileTreeModel?
    let gitStatusIndex: WorkspaceFileTreeGitStatusIndex?
    let gitStore: GitStore?
    let changeCount: Int
    let agentSessions: [HostedAgentSessionSummary]
    let workflowState: WindowFeature.WorkflowWorkspaceState
    let portsByWorkspaceID: [Workspace.ID: [WorkspacePort]]
    let repositorySettingsStore: RepositorySettingsStore
    let onSelectSidebar: (WorkspaceSidebarMode) -> Void
    let onPreviewFile: (Workspace.ID, URL) -> Void
    let onOpenFile: (Workspace.ID, URL) -> Void
    let onAddFileToAgent: (Workspace.ID, URL) -> Void
    let onRenameFile: (Workspace.ID, URL) -> Void
    let onDeleteFiles: (Workspace.ID, [URL]) -> Void
    let onOpenDiff: (Workspace.ID, String, Bool, Bool) -> Void
    let onAddDiffToAgent: (Workspace.ID, String, Bool) -> Void
    let onCreateAgentSession: (Workspace.ID) -> Void
    let onOpenAgentSession: (Workspace.ID, AgentSessionID) -> Void
    let onCreateWorkflowDefinition: (Workspace.ID) -> Void
    let onOpenWorkflowDefinition: (Workspace.ID, String) -> Void
    let onStartWorkflowDefinition: (Workspace.ID, String) -> Void
    let onDeleteWorkflowDefinition: (Workspace.ID, String) -> Void
    let onOpenWorkflowRun: (Workspace.ID, UUID) -> Void
    let onDeleteWorkflowRun: (Workspace.ID, UUID) -> Void
    let onOpenPort: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onCopyPortURL: (WorkspacePort, RepositoryPortLabel?) -> Void
    let onStopPortProcess: (WorkspacePort, Int32) -> Void

    var body: some View {
        let ports = selectedWorkspaceID.flatMap { portsByWorkspaceID[$0] } ?? []

        UnifiedWorkspaceSidebar(
            selection: activeSidebar,
            onSelect: onSelectSidebar,
            changeCount: changeCount,
            portCount: ports.count,
            agentCount: agentSessions.count,
            workflowCount: workflowState.definitions.count + workflowState.runs.count
        ) {
            SidebarContentView(
                model: fileTreeModel,
                activeDirectory: currentWorktree?.workingDirectory ?? selectedRepositoryRootURL,
                gitStatusIndex: gitStatusIndex,
                onPreviewFile: { url in
                    guard let selectedWorkspaceID else { return }
                    onPreviewFile(selectedWorkspaceID, url)
                },
                onOpenFile: { url in
                    guard let selectedWorkspaceID else { return }
                    onOpenFile(selectedWorkspaceID, url)
                },
                onAddToChat: { url in
                    guard let selectedWorkspaceID else { return }
                    onAddFileToAgent(selectedWorkspaceID, url)
                },
                onRenameItem: { url in
                    guard let selectedWorkspaceID else { return }
                    onRenameFile(selectedWorkspaceID, url)
                },
                onDeleteItems: { urls in
                    guard let selectedWorkspaceID else { return }
                    onDeleteFiles(selectedWorkspaceID, urls)
                },
                showsTrailingBorder: false
            )
        } changesContent: {
            if let gitStore {
                GitSidebarView(
                    store: gitStore,
                    onPreviewDiff: { path, isStaged in
                        guard let selectedWorkspaceID else { return }
                        onOpenDiff(selectedWorkspaceID, path, isStaged, false)
                    },
                    onOpenDiff: { path, isStaged in
                        guard let selectedWorkspaceID else { return }
                        onOpenDiff(selectedWorkspaceID, path, isStaged, true)
                    },
                    onAddDiffToChat: { path, isStaged in
                        guard let selectedWorkspaceID else { return }
                        onAddDiffToAgent(selectedWorkspaceID, path, isStaged)
                    }
                )
            }
        } portsContent: {
            WorkspacePortsSidebarView(
                ports: ports,
                labelsByPort: repositorySettingsStore.portLabelsByPort(
                    for: currentWorktree?.repositoryRootURL
                ),
                onOpen: onOpenPort,
                onCopyURL: onCopyPortURL,
                onStopProcess: onStopPortProcess
            )
        } agentsContent: {
            AgentSessionsSidebarSection(
                sessions: agentSessions,
                onCreateSession: {
                    guard let selectedWorkspaceID else { return }
                    onCreateAgentSession(selectedWorkspaceID)
                },
                onOpenSession: { sessionID in
                    guard let selectedWorkspaceID else { return }
                    onOpenAgentSession(selectedWorkspaceID, sessionID)
                }
            )
        } workflowsContent: {
            WorkflowSidebarSectionView(
                definitions: workflowState.definitions,
                runs: workflowState.runs,
                onCreateWorkflow: {
                    guard let selectedWorkspaceID else { return }
                    onCreateWorkflowDefinition(selectedWorkspaceID)
                },
                onOpenDefinition: { definitionID in
                    guard let selectedWorkspaceID else { return }
                    onOpenWorkflowDefinition(selectedWorkspaceID, definitionID)
                },
                onStartDefinition: { definitionID in
                    guard let selectedWorkspaceID else { return }
                    onStartWorkflowDefinition(selectedWorkspaceID, definitionID)
                },
                onDeleteDefinition: { definitionID in
                    guard let selectedWorkspaceID else { return }
                    onDeleteWorkflowDefinition(selectedWorkspaceID, definitionID)
                },
                onOpenRun: { runID in
                    guard let selectedWorkspaceID else { return }
                    onOpenWorkflowRun(selectedWorkspaceID, runID)
                },
                onDeleteRun: { runID in
                    guard let selectedWorkspaceID else { return }
                    onDeleteWorkflowRun(selectedWorkspaceID, runID)
                }
            )
        }
    }
}

@MainActor
private struct AgentSessionsSidebarSection: View {
    @Environment(\.devysTheme) private var theme

    let sessions: [HostedAgentSessionSummary]
    let onCreateSession: () -> Void
    let onOpenSession: (AgentSessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            ActionButton("New Agent Session", icon: "person.crop.circle.badge.plus") {
                onCreateSession()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if sessions.isEmpty {
                Text("No active sessions in this workspace.")
                    .font(DevysTypography.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, DevysSpacing.space3)
                    .padding(.vertical, 4)
            } else {
                ForEach(sessions) { session in
                    Button {
                        onOpenSession(session.sessionID)
                    } label: {
                        HStack(spacing: 10) {
                            DevysIcon(session.tabIcon, size: 14, weight: .semibold)
                                .foregroundStyle(theme.accent)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.tabTitle)
                                    .font(DevysTypography.body)
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)

                                Text(session.stateSummary)
                                    .font(DevysTypography.caption)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if session.tabIsBusy {
                                StatusDot(.running)
                            }
                        }
                        .padding(.horizontal, DevysSpacing.space3)
                        .padding(.vertical, 8)
                        .background(theme.card)
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                                .stroke(theme.border, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.bottom, DevysSpacing.space3)
    }
}
