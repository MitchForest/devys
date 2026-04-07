// ContentView+LaunchActions.swift
// Workspace launcher and startup profile actions.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split
import Workspace

private struct ResolvedWorkspaceTerminalLaunch {
    let launch: (terminalID: UUID, command: String)
    let resolvedCommand: ResolvedLauncherCommand
}

@MainActor
extension ContentView {
    func launchClaudeForSelectedWorkspace() {
        launchSelectedWorkspaceTerminal(kind: .claude, label: "Claude")
    }

    func launchCodexForSelectedWorkspace() {
        launchSelectedWorkspaceTerminal(kind: .codex, label: "Codex")
    }

    func runSelectedWorkspaceProfile() {
        guard let worktree = activeWorktree else { return }

        let resolvedProfile = resolveDefaultStartupProfile(for: worktree)
        guard let resolvedProfile else { return }

        Task { @MainActor in
            let launchResult = await launchStartupProfile(resolvedProfile, in: worktree)

            workspaceRunStore.setRunning(
                worktreeId: worktree.id,
                profileID: resolvedProfile.profile.id,
                terminalIDs: launchResult.terminalIDs,
                backgroundProcessIDs: launchResult.backgroundProcessIDs
            )
            persistTerminalRelaunchSnapshotIfNeeded()

            if !launchResult.failures.isEmpty {
                showLauncherUnavailableAlert(
                    title: "Run Profile Started With Failures",
                    message: launchResult.failures.joined(separator: "\n")
                )
            }
        }
    }

    func editSelectedWorkspaceProfiles() {
        openRepositorySettings()
    }

    func stopSelectedWorkspaceProfile() {
        guard let worktree = activeWorktree else { return }

        if let state = workspaceRunStore.state(for: worktree.id) {
            for terminalID in state.terminalIDs {
                shutdownWorkspaceTerminalSession(id: terminalID, in: worktree.id)
            }
            for processID in state.backgroundProcessIDs {
                workspaceBackgroundProcessRegistry.shutdown(id: processID, in: worktree.id)
            }
        }
        workspaceRunStore.clearWorktree(worktree.id)
        syncCatalogPortState()
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    private func launchSelectedWorkspaceTerminal(
        kind: BuiltInLauncherKind,
        label: String
    ) {
        guard let worktree = activeWorktree else { return }
        guard let resolvedLaunch = resolveWorkspaceTerminalLaunch(
            kind: kind,
            label: label,
            worktree: worktree
        ) else { return }

        Task { @MainActor in
            let trace = WorkspacePerformanceRecorder.begin(
                "terminal-launch",
                context: [
                    "workspace_id": worktree.id,
                    "source": kind.rawValue
                ]
            )
            do {
                let session = try await createWorkspaceTerminalSession(
                    in: worktree.id,
                    workingDirectory: worktree.workingDirectory,
                    requestedCommand: resolvedLaunch.resolvedCommand.executionBehavior == .runImmediately
                        ? resolvedLaunch.launch.command
                        : nil,
                    stagedCommand: resolvedLaunch.resolvedCommand.executionBehavior == .stageInTerminal
                        ? resolvedLaunch.launch.command
                        : nil,
                    id: resolvedLaunch.launch.terminalID
                )
                openInPermanentTab(content: .terminal(workspaceID: worktree.id, id: session.id))
                persistTerminalRelaunchSnapshotIfNeeded()
                WorkspacePerformanceRecorder.end(trace)
            } catch {
                WorkspacePerformanceRecorder.end(
                    trace,
                    outcome: "failure",
                    context: ["error": error.localizedDescription]
                )
                showLauncherUnavailableAlert(
                    title: "\(label) Launcher Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func resolveWorkspaceTerminalLaunch(
        kind: BuiltInLauncherKind,
        label: String,
        worktree: Worktree
    ) -> ResolvedWorkspaceTerminalLaunch? {
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        let launcher = switch kind {
        case .claude: settings.claudeLauncher
        case .codex: settings.codexLauncher
        }

        let resolvedCommand: ResolvedLauncherCommand
        do {
            resolvedCommand = try RepositoryLaunchPlanner.resolveLauncher(launcher, kind: kind)
        } catch {
            showLauncherUnavailableAlert(
                title: "\(label) Launcher Is Incomplete",
                message: error.localizedDescription
            )
            openRepositorySettings()
            return nil
        }

        let launch = prepareAgentTerminalLaunch(
            kind: kind,
            resolvedCommand: resolvedCommand.command,
            worktree: worktree
        )
        return ResolvedWorkspaceTerminalLaunch(launch: launch, resolvedCommand: resolvedCommand)
    }

    private func resolveDefaultStartupProfile(for worktree: Worktree) -> ResolvedStartupProfile? {
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        do {
            return try RepositoryLaunchPlanner.resolveDefaultStartupProfile(
                in: settings,
                workspaceRoot: worktree.workingDirectory
            )
        } catch {
            showLauncherUnavailableAlert(
                title: "Run Profile Not Available",
                message: error.localizedDescription
            )
            openRepositorySettings()
            return nil
        }
    }

    private func launchStartupProfile(
        _ resolvedProfile: ResolvedStartupProfile,
        in worktree: Worktree
    ) async -> (terminalIDs: [UUID], backgroundProcessIDs: [UUID], failures: [String]) {
        var launchedTerminalIDs: [UUID] = []
        var launchedProcessIDs: [UUID] = []
        var failures: [String] = []
        var shouldRefreshPorts = false
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first

        for step in resolvedProfile.steps {
            do {
                switch step.launchMode {
                case .newTab:
                    let terminalID = try await launchTerminalStep(
                        step,
                        in: worktree.id,
                        paneID: targetPane
                    )
                    launchedTerminalIDs.append(terminalID)
                case .split:
                    let terminalID = try await launchSplitTerminalStep(step, in: worktree.id)
                    launchedTerminalIDs.append(terminalID)
                case .backgroundManagedProcess:
                    let backgroundProcess = try workspaceBackgroundProcessRegistry.launch(
                        in: worktree.id,
                        stepID: step.id,
                        displayName: step.displayName,
                        workingDirectory: step.workingDirectory,
                        command: step.command,
                        environment: step.environment
                    ) { processID, _ in
                        workspaceRunStore.removeBackgroundProcess(processID)
                        syncCatalogPortState()
                    }
                    launchedProcessIDs.append(backgroundProcess.id)
                    shouldRefreshPorts = true
                }
            } catch {
                failures.append("\(step.displayName): \(error.localizedDescription)")
            }
        }

        if shouldRefreshPorts {
            syncCatalogPortState()
        }

        return (launchedTerminalIDs, launchedProcessIDs, failures)
    }

    private func launchTerminalStep(
        _ step: ResolvedStartupProfileStep,
        in workspaceID: Workspace.ID,
        paneID: PaneID?
    ) async throws -> UUID {
        let session = try await createWorkspaceTerminalSession(
            in: workspaceID,
            workingDirectory: step.workingDirectory,
            requestedCommand: step.shellCommand
        )
        let content = TabContent.terminal(workspaceID: workspaceID, id: session.id)
        let targetPane = paneID ?? controller.focusedPaneId ?? controller.allPaneIds.first
        guard let targetPane else {
            shutdownWorkspaceTerminalSession(id: session.id, in: workspaceID)
            throw NSError(domain: "DevysStartupProfiles", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No target pane is available for \(step.displayName)."
            ])
        }
        guard createTab(in: targetPane, content: content) != nil else {
            shutdownWorkspaceTerminalSession(id: session.id, in: workspaceID)
            throw NSError(domain: "DevysStartupProfiles", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not open a terminal tab for \(step.displayName)."
            ])
        }
        persistTerminalRelaunchSnapshotIfNeeded()
        return session.id
    }

    private func launchSplitTerminalStep(
        _ step: ResolvedStartupProfileStep,
        in workspaceID: Workspace.ID
    ) async throws -> UUID {
        let sourcePane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let sourcePane,
              let splitPane = controller.splitPane(sourcePane, orientation: .horizontal)
        else {
            throw NSError(domain: "DevysStartupProfiles", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not create a split for \(step.displayName)."
            ])
        }

        return try await launchTerminalStep(step, in: workspaceID, paneID: splitPane)
    }
}
