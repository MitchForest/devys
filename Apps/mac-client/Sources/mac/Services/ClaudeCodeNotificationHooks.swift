// ClaudeCodeNotificationHooks.swift
// Devys - Project-local Claude Code hook installation.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

enum ClaudeCodeNotificationHooks {
    private static let notificationMarker = "--workspace-notify-hook --source claude"
    private static let waitingCommand =
        "\"$DEVYS_EXECUTABLE_PATH\" --workspace-notify-hook --source claude --kind waiting"
    private static let completedCommand =
        "\"$DEVYS_EXECUTABLE_PATH\" --workspace-notify-hook --source claude --kind completed"

    static func ensureInstalled(in workspaceRoot: URL) throws {
        let claudeDirectory = workspaceRoot.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true
        )

        let settingsURL = claudeDirectory.appendingPathComponent("settings.local.json")
        var settings = try loadSettings(from: settingsURL)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        hooks["Notification"] = mergedGroups(
            existing: hooks["Notification"] as? [[String: Any]] ?? [],
            additions: [notificationGroup()]
        )

        hooks["Stop"] = mergedGroups(
            existing: hooks["Stop"] as? [[String: Any]] ?? [],
            additions: [stopGroup()]
        )

        hooks["StopFailure"] = mergedGroups(
            existing: hooks["StopFailure"] as? [[String: Any]] ?? [],
            additions: [stopGroup()]
        )

        settings["hooks"] = hooks
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func loadSettings(from url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private static func mergedGroups(
        existing: [[String: Any]],
        additions: [[String: Any]]
    ) -> [[String: Any]] {
        let retainedGroups = existing.filter { !containsDevysHook(group: $0) }
        return retainedGroups + additions
    }

    private static func containsDevysHook(group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(notificationMarker)
        }
    }

    private static func notificationGroup() -> [String: Any] {
        [
            "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
            "hooks": [commandHook(command: waitingCommand)]
        ]
    }

    private static func stopGroup() -> [String: Any] {
        [
            "hooks": [commandHook(command: completedCommand)]
        ]
    }

    private static func commandHook(command: String) -> [String: Any] {
        [
            "type": "command",
            "command": command,
            "async": true
        ]
    }
}
