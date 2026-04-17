// ContentView+AgentNotifications.swift
// Devys - Terminal agent notification launch helpers.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Workspace

@MainActor
extension ContentView {
    func prepareAgentTerminalLaunch(
        kind: BuiltInLauncherKind,
        resolvedCommand: String,
        worktree: Worktree
    ) -> (terminalID: UUID, command: String) {
        let terminalID = UUID()

        switch kind {
        case .claude:
            installClaudeNotifications(in: worktree.workingDirectory)
        case .codex:
            break
        }

        return (
            terminalID: terminalID,
            command: wrappedLauncherCommand(
                resolvedCommand,
                workspaceID: worktree.id,
                terminalID: terminalID,
                executablePath: devysExecutablePath()
            )
        )
    }

    private func installClaudeNotifications(in workspaceRoot: URL) {
        do {
            try ClaudeCodeNotificationHooks.ensureInstalled(in: workspaceRoot)
        } catch {
            showLauncherUnavailableAlert(
                title: "Claude Notifications Unavailable",
                message: """
                Devys could not install Claude Code hooks for this workspace.

                \(error.localizedDescription)
                """
            )
        }
    }

    private func wrappedLauncherCommand(
        _ command: String,
        workspaceID: Workspace.ID,
        terminalID: UUID,
        executablePath: String?
    ) -> String {
        var environment = [
            ("DEVYS_WORKSPACE_ID", workspaceID),
            ("DEVYS_TERMINAL_ID", terminalID.uuidString)
        ]
        if let executablePath, !executablePath.isEmpty {
            environment.append(("DEVYS_EXECUTABLE_PATH", executablePath))
        }
        return envWrappedShellCommand(command, environment: environment)
    }

    private func devysExecutablePath() -> String? {
        Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first
    }
}

func envWrappedShellCommand(
    _ command: String,
    environment: [(key: String, value: String)]
) -> String {
    guard !environment.isEmpty else { return command }

    let assignments = environment.map { key, value in
        "\(key)=\(shellQuoted(value))"
    }
    return (["env", "-u", "NO_COLOR"] + assignments + [command]).joined(separator: " ")
}

func shellQuoted(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    if value.unicodeScalars.allSatisfy({ scalar in
        CharacterSet.alphanumerics.contains(scalar) || "/-._:".unicodeScalars.contains(scalar)
    }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
