// ContentView+LaunchActions.swift
// Workspace launcher and startup profile actions.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import GhosttyTerminal
import Split
import UI
import Workspace

private struct ResolvedWorkspaceTerminalLaunch {
    let launch: (terminalID: UUID, command: String)
    let resolvedCommand: ResolvedLauncherCommand
    let tabIcon: String
}

@MainActor
extension ContentView {
    func launchClaudeForSelectedWorkspace(preferredPaneID: PaneID? = nil) {
        launchSelectedWorkspaceTerminal(
            kind: .claude,
            label: "Claude",
            preferredPaneID: preferredPaneID
        )
    }

    func launchCodexForSelectedWorkspace(preferredPaneID: PaneID? = nil) {
        launchSelectedWorkspaceTerminal(
            kind: .codex,
            label: "Codex",
            preferredPaneID: preferredPaneID
        )
    }

    func isLauncherConfiguredForSelectedWorkspace(
        kind: BuiltInLauncherKind
    ) -> Bool {
        guard let worktree = activeWorktree else { return false }
        return isWorkspaceLauncherConfigured(kind: kind, worktree: worktree)
    }

    private func launchSelectedWorkspaceTerminal(
        kind: BuiltInLauncherKind,
        label: String,
        preferredPaneID: PaneID? = nil
    ) {
        guard let worktree = activeWorktree else { return }
        if let preferredPaneID {
            store.send(.setWorkspaceFocusedPaneID(workspaceID: worktree.id, paneID: preferredPaneID))
            renderWorkspaceLayout(for: worktree.id)
        }
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
                let session = try await createResolvedWorkspaceTerminalSession(
                    for: resolvedLaunch,
                    in: worktree
                )
                try presentResolvedWorkspaceTerminalSession(
                    session,
                    workspaceID: worktree.id,
                    label: label,
                    preferredPaneID: preferredPaneID
                )
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
        return ResolvedWorkspaceTerminalLaunch(
            launch: launch,
            resolvedCommand: resolvedCommand,
            tabIcon: terminalTabIcon(for: kind)
        )
    }

    private func createResolvedWorkspaceTerminalSession(
        for resolvedLaunch: ResolvedWorkspaceTerminalLaunch,
        in worktree: Worktree
    ) async throws -> GhosttyTerminalSession {
        try await createWorkspaceTerminalSession(
            in: worktree.id,
            workingDirectory: worktree.workingDirectory,
            requestedCommand: resolvedLaunch.resolvedCommand.executionBehavior == .runImmediately
                ? resolvedLaunch.launch.command
                : nil,
            stagedCommand: resolvedLaunch.resolvedCommand.executionBehavior == .stageInTerminal
                ? resolvedLaunch.launch.command
                : nil,
            tabIcon: resolvedLaunch.tabIcon,
            id: resolvedLaunch.launch.terminalID
        )
    }

    private func presentResolvedWorkspaceTerminalSession(
        _ session: GhosttyTerminalSession,
        workspaceID: Workspace.ID,
        label: String,
        preferredPaneID: PaneID?
    ) throws {
        let content = WorkspaceTabContent.terminal(workspaceID: workspaceID, id: session.id)
        if let preferredPaneID {
            guard createTab(in: preferredPaneID, content: content) != nil else {
                shutdownWorkspaceTerminalSession(id: session.id, in: workspaceID)
                throw NSError(domain: "DevysLauncher", code: 4, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not open a terminal tab for \(label)."
                ])
            }
        } else {
            openInPermanentTab(content: content)
        }
    }

    private func isWorkspaceLauncherConfigured(
        kind: BuiltInLauncherKind,
        worktree: Worktree
    ) -> Bool {
        let settings = repositorySettingsStore.settings(for: worktree.repositoryRootURL)
        let launcher = switch kind {
        case .claude: settings.claudeLauncher
        case .codex: settings.codexLauncher
        }

        do {
            _ = try RepositoryLaunchPlanner.resolveLauncher(launcher, kind: kind)
            return true
        } catch {
            return false
        }
    }

    private func terminalTabIcon(for kind: BuiltInLauncherKind) -> String {
        switch kind {
        case .claude:
            DevysIconName.claudeCode
        case .codex:
            DevysIconName.codex
        }
    }

    func executeRunProfileLaunch(_ request: WindowFeature.RunProfileLaunchRequest) async {
        guard let worktree = windowWorkspaceContext(for: request.workspaceID)?.worktree else { return }

        let launchResult = await launchStartupProfile(
            request.resolvedProfile,
            in: worktree
        )
        store.send(
            .runProfileLaunchCompleted(
                WindowFeature.RunProfileLaunchResult(
                    workspaceID: worktree.id,
                    profileID: request.resolvedProfile.profile.id,
                    terminalIDs: launchResult.terminalIDs,
                    backgroundProcessIDs: launchResult.backgroundProcessIDs,
                    failures: launchResult.failures
                )
            )
        )
        persistTerminalRelaunchSnapshotIfNeeded()

        if !launchResult.failures.isEmpty {
            showLauncherUnavailableAlert(
                title: "Run Profile Started With Failures",
                message: launchResult.failures.joined(separator: "\n")
            )
        }
    }

    func executeRunProfileStop(_ request: WindowFeature.RunProfileStopRequest) async {
        for terminalID in request.terminalIDs {
            shutdownWorkspaceTerminalSession(id: terminalID, in: request.workspaceID)
        }
        for processID in request.backgroundProcessIDs {
            workspaceBackgroundProcessRegistry.shutdown(id: processID, in: request.workspaceID)
        }
        store.send(.runProfileStopCompleted(request.workspaceID))
        persistTerminalRelaunchSnapshotIfNeeded()
    }

    private func launchStartupProfile(
        _ resolvedProfile: ResolvedStartupProfile,
        in worktree: Worktree
    ) async -> (terminalIDs: [UUID], backgroundProcessIDs: [UUID], failures: [String]) {
        var launchedTerminalIDs: [UUID] = []
        var launchedProcessIDs: [UUID] = []
        var failures: [String] = []
        let targetPane = targetPaneID(workspaceID: worktree.id)

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
                        store.send(.removeWorkspaceRunBackgroundProcess(processID))
                    }
                    launchedProcessIDs.append(backgroundProcess.id)
                }
            } catch {
                failures.append("\(step.displayName): \(error.localizedDescription)")
            }
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
        let content = WorkspaceTabContent.terminal(workspaceID: workspaceID, id: session.id)
        let targetPane = paneID ?? targetPaneID(workspaceID: workspaceID)
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
        let sourcePane = targetPaneID(workspaceID: workspaceID)
        guard let sourcePane,
              let splitPane = splitPane(sourcePane, orientation: .horizontal, workspaceID: workspaceID)
        else {
            throw NSError(domain: "DevysStartupProfiles", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not create a split for \(step.displayName)."
            ])
        }

        return try await launchTerminalStep(step, in: workspaceID, paneID: splitPane)
    }
}
