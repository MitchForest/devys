// ContentView+CommandPaletteCatalog.swift
// Command palette item and section modeling for the workspace shell.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import UI
import Workspace

@MainActor
struct ContentViewCommandPaletteCatalog {
    let repositories: [Repository]
    let visibleNavigatorWorkspaces: [(repositoryID: Repository.ID, workspace: Worktree)]
    let workspaceStatesByID: [Worktree.ID: WorktreeState]
    let activeWorktree: Worktree?
    let agentSessions: [HostedAgentSessionSummary]
    let workflowState: WindowFeature.WorkflowWorkspaceState
    let repositorySettingsStore: RepositorySettingsStore
    let operationalState: WorkspaceOperationalState
    let appSettings: AppSettings

    var homeSections: [CommandPaletteSection] {
        sections(from: items)
    }

    func filteredSections(query: String) -> [CommandPaletteSection] {
        sections(from: filteredItems(query: query))
    }

    func visibleItems(query: String) -> [WorkspaceSearchItem] {
        let sourceItems = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? items
            : filteredItems(query: query)
        return sectionEntries(from: sourceItems).flatMap { $0.1 }
    }
}

private extension ContentViewCommandPaletteCatalog {
    private func filteredItems(query: String) -> [WorkspaceSearchItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return items }
        return items.filter { item in
            item.title.lowercased().contains(normalizedQuery)
                || item.subtitle.lowercased().contains(normalizedQuery)
                || item.keywords.contains { $0.lowercased().contains(normalizedQuery) }
        }
    }

    private func sections(from sourceItems: [WorkspaceSearchItem]) -> [CommandPaletteSection] {
        sectionEntries(from: sourceItems).map { title, sectionItems in
            CommandPaletteSection(
                title: title,
                items: sectionItems.map(paletteItem(for:))
            )
        }
    }

    private func sectionEntries(from sourceItems: [WorkspaceSearchItem]) -> [(String, [WorkspaceSearchItem])] {
        let orderedTitles = [
            "Projects",
            "Navigation",
            "Agents",
            "Workflows",
            "Execution",
            "Attention"
        ]

        let grouped = Dictionary(grouping: sourceItems, by: sectionTitle(for:))
        return orderedTitles.compactMap { title in
            guard let sectionItems = grouped[title], !sectionItems.isEmpty else { return nil }
            return (title, sectionItems)
        }
    }

    private func paletteItem(for item: WorkspaceSearchItem) -> CommandPaletteItem {
        CommandPaletteItem(
            icon: item.systemImage,
            title: item.title,
            subtitle: item.subtitle,
            shortcut: item.accessory
        )
    }

    private func sectionTitle(for item: WorkspaceSearchItem) -> String {
        switch item.action {
        case .command(.addRepository),
             .command(.initializeRepository),
             .command(.createWorkspace),
             .command(.importWorktrees):
            return "Projects"

        case .command(.selectRepository),
             .command(.selectWorkspace),
             .command(.revealCurrentWorkspaceInNavigator):
            return "Navigation"

        case .command(.openAgents),
             .command(.focusAgentSession):
            return "Agents"

        case .command(.createWorkflow),
             .command(.openWorkflowDefinition),
             .command(.openWorkflowRun):
            return "Workflows"

        case .command(.launchShell),
             .command(.launchClaude),
             .command(.launchCodex),
             .command(.runDefaultProfile):
            return "Execution"

        case .command(.jumpToLatestUnreadWorkspace):
            return "Attention"

        case .openFile:
            return "Files"

        case .openTextSearchMatch:
            return "Matches"
        }
    }

    private var items: [WorkspaceSearchItem] {
        var items: [WorkspaceSearchItem] = [
            WorkspaceSearchItem(
                action: .command(.addRepository),
                title: "Add Repository",
                subtitle: "Open a local project or import a Git repository",
                systemImage: "folder.badge.plus",
                keywords: ["repository", "project", "import", "add", "open"],
                accessory: "⌘O"
            )
        ]

        for repository in repositories {
            items.append(
                WorkspaceSearchItem(
                    action: .command(.selectRepository(repository.id)),
                    title: "Switch to \(repository.displayName)",
                    subtitle: repository.rootURL.path,
                    systemImage: "shippingbox",
                    keywords: ["repository", "switch", repository.displayName, repository.rootURL.path],
                    accessory: nil
                )
            )
            if repository.isGitRepository {
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.createWorkspace(repository.id)),
                        title: "Create Workspace in \(repository.displayName)",
                        subtitle: "New branch, existing branch, or pull request",
                        systemImage: "plus.circle",
                        keywords: ["workspace", "create", "branch", repository.displayName],
                        accessory: nil
                    )
                )
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.importWorktrees(repository.id)),
                        title: "Import Worktrees in \(repository.displayName)",
                        subtitle: "Attach existing git worktrees to this repository",
                        systemImage: "square.and.arrow.down",
                        keywords: ["workspace", "worktree", "import", repository.displayName],
                        accessory: nil
                    )
                )
            } else {
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.initializeRepository(repository.id)),
                        title: "Initialize Git in \(repository.displayName)",
                        subtitle: "Create a new Git repository for this local project",
                        systemImage: "arrow.triangle.branch",
                        keywords: ["git", "init", "initialize", repository.displayName],
                        accessory: nil
                    )
                )
            }
        }

        for entry in visibleNavigatorWorkspaces {
            let workspaceName = workspaceDisplayName(for: entry.workspace)
            items.append(
                WorkspaceSearchItem(
                    action: .command(
                        .selectWorkspace(
                            repositoryID: entry.repositoryID,
                            workspaceID: entry.workspace.id
                        )
                    ),
                    title: "Switch to \(workspaceName)",
                    subtitle: "\(entry.workspace.name) • \(entry.workspace.workingDirectory.path)",
                    systemImage: "arrow.triangle.branch",
                    keywords: [
                        "workspace",
                        "switch",
                        entry.workspace.name,
                        workspaceName,
                        entry.workspace.workingDirectory.path
                    ],
                    accessory: nil
                )
            )
        }

        if let activeWorktree {
            items.append(
                WorkspaceSearchItem(
                    action: .command(.openAgents),
                    title: "New Agent Session",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "person.crop.circle.badge.plus",
                    keywords: ["agent", "agents", "chat", "assistant", "new"],
                    accessory: nil
                )
            )

            items.append(
                WorkspaceSearchItem(
                    action: .command(.createWorkflow),
                    title: "New Workflow",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    keywords: ["workflow", "phase", "plan", "new", "create"],
                    accessory: nil
                )
            )

            if let activeRun = workflowState.runs.first(where: { $0.status.isActive }) {
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.openWorkflowRun(activeRun.id)),
                        title: "Open Active Workflow Run",
                        subtitle: activeRun.currentPhaseTitle ?? activeRun.displayStatus,
                        systemImage: "play.circle.fill",
                        keywords: ["workflow", "run", "active", activeRun.displayStatus],
                        accessory: nil
                    )
                )
            }

            if let latestDefinition = workflowState.definitions.first {
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.openWorkflowDefinition(latestDefinition.id)),
                        title: "Open Workflow Definition",
                        subtitle: latestDefinition.name.isEmpty ? "Untitled Workflow" : latestDefinition.name,
                        systemImage: "square.and.pencil",
                        keywords: [
                            "workflow",
                            "definition",
                            latestDefinition.name,
                            latestDefinition.planFilePath
                        ],
                        accessory: nil
                    )
                )
            }

            for session in agentSessions {
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.focusAgentSession(session.sessionID)),
                        title: "Open \(session.tabTitle)",
                        subtitle: session.stateSummary,
                        systemImage: session.tabIcon,
                        keywords: [
                            "agent",
                            "session",
                            session.tabTitle,
                            session.stateSummary
                        ],
                        accessory: nil
                    )
                )
            }

            items.append(
                WorkspaceSearchItem(
                    action: .command(.launchShell),
                    title: "Launch Shell",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: "terminal",
                    keywords: ["shell", "terminal", "launch"],
                    accessory: appSettings.shortcuts.binding(for: .launchShell).displayString
                )
            )
            items.append(
                WorkspaceSearchItem(
                    action: .command(.launchClaude),
                    title: "Launch Claude",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: DevysIconName.claudeCode,
                    keywords: ["claude", "agent", "launch"],
                    accessory: appSettings.shortcuts.binding(for: .launchClaude).displayString
                )
            )
            items.append(
                WorkspaceSearchItem(
                    action: .command(.launchCodex),
                    title: "Launch Codex",
                    subtitle: activeWorktree.workingDirectory.path,
                    systemImage: DevysIconName.codex,
                    keywords: ["codex", "agent", "launch"],
                    accessory: appSettings.shortcuts.binding(for: .launchCodex).displayString
                )
            )
            items.append(
                WorkspaceSearchItem(
                    action: .command(.revealCurrentWorkspaceInNavigator),
                    title: "Reveal Current Workspace in Navigator",
                    subtitle: workspaceDisplayName(for: activeWorktree),
                    systemImage: "sidebar.left",
                    keywords: ["reveal", "navigator", "workspace", "sidebar"],
                    accessory: nil
                )
            )

            if defaultRunProfileAvailable(for: activeWorktree) {
                items.append(
                    WorkspaceSearchItem(
                        action: .command(.runDefaultProfile),
                        title: "Run Default Profile",
                        subtitle: activeWorktree.workingDirectory.path,
                        systemImage: "play.fill",
                        keywords: ["run", "profile", "startup"],
                        accessory: nil
                    )
                )
            }
        }

        if operationalState.latestUnreadNotification() != nil {
            items.append(
                WorkspaceSearchItem(
                    action: .command(.jumpToLatestUnreadWorkspace),
                    title: "Jump to Latest Unread Workspace",
                    subtitle: "Open the newest workspace attention item",
                    systemImage: "bell.badge",
                    keywords: ["notification", "unread", "attention", "jump"],
                    accessory: appSettings.shortcuts.binding(for: .jumpToLatestUnreadWorkspace).displayString
                )
            )
        }

        return items
    }

    private func workspaceDisplayName(for worktree: Worktree) -> String {
        let override = workspaceStatesByID[worktree.id]?.displayNameOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return override
        }
        return worktree.name
    }

    private func defaultRunProfileAvailable(for worktree: Worktree) -> Bool {
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        guard let defaultStartupProfileID = settings.defaultStartupProfileID else { return false }
        return settings.startupProfiles.contains { $0.id == defaultStartupProfileID }
    }
}
