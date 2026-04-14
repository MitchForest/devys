// WorkspaceShellShortcutSupport.swift
// App-side presentation and conflict helpers for workspace shell shortcuts.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import Workspace

extension WorkspaceShellShortcutAction {
    var title: String {
        switch self {
        case .nextWorkspace:
            "Next Workspace"
        case .previousWorkspace:
            "Previous Workspace"
        case .toggleSidebar:
            "Toggle Sidebar"
        case .toggleNavigator:
            "Toggle Navigator"
        case .launchShell:
            "Launch Shell"
        case .launchClaude:
            "Launch Claude"
        case .launchCodex:
            "Launch Codex"
        case .jumpToLatestUnreadWorkspace:
            "Jump to Latest Unread Workspace"
        }
    }

    var description: String {
        switch self {
        case .nextWorkspace:
            "Move to the next visible workspace in the navigator"
        case .previousWorkspace:
            "Move to the previous visible workspace in the navigator"
        case .toggleSidebar:
            "Show or hide the active workspace sidebar"
        case .toggleNavigator:
            "Show or hide the repository navigator"
        case .launchShell:
            "Open a shell terminal in the selected workspace"
        case .launchClaude:
            "Launch Claude in the selected workspace"
        case .launchCodex:
            "Launch Codex in the selected workspace"
        case .jumpToLatestUnreadWorkspace:
            "Jump to the workspace with the latest unread attention"
        }
    }
}

struct WorkspaceShellShortcutConflictSet {
    let messagesByAction: [WorkspaceShellShortcutAction: [String]]

    var hasConflicts: Bool {
        !messagesByAction.isEmpty
    }

    func messages(for action: WorkspaceShellShortcutAction) -> [String] {
        messagesByAction[action] ?? []
    }
}

func detectWorkspaceShellShortcutConflicts(
    in settings: WorkspaceShellShortcutSettings
) -> WorkspaceShellShortcutConflictSet {
    let bindingsByAction = Dictionary(
        uniqueKeysWithValues: WorkspaceShellShortcutAction.allCases.map { action in
            (action, settings.binding(for: action))
        }
    )

    var messagesByAction: [WorkspaceShellShortcutAction: [String]] = [:]
    let duplicates = Dictionary(grouping: bindingsByAction) { $0.value }
        .filter { $0.value.count > 1 }

    for entry in duplicates.values {
        let titles = entry.map(\.key.title).sorted()
        for action in entry.map(\.key) {
            let otherTitles = titles.filter { $0 != action.title }.joined(separator: ", ")
            messagesByAction[action, default: []].append("Also used by \(otherTitles).")
        }
    }

    for (action, binding) in bindingsByAction {
        for reserved in reservedWorkspaceShellShortcutBindings where reserved.binding == binding {
            messagesByAction[action, default: []].append("Conflicts with \(reserved.title).")
        }
    }

    return WorkspaceShellShortcutConflictSet(messagesByAction: messagesByAction)
}

private struct ReservedWorkspaceShellShortcutBinding {
    let binding: ShortcutBinding
    let title: String
}

private let reservedWorkspaceShellShortcutBindings: [ReservedWorkspaceShellShortcutBinding] = [
    .init(
        binding: ShortcutBinding(key: "o", modifiers: ShortcutModifierSet(command: true)),
        title: "Add Repository"
    ),
    .init(
        binding: ShortcutBinding(key: "s", modifiers: ShortcutModifierSet(command: true)),
        title: "Save"
    ),
    .init(
        binding: ShortcutBinding(key: "s", modifiers: ShortcutModifierSet(command: true, shift: true)),
        title: "Save As"
    ),
    .init(
        binding: ShortcutBinding(key: "s", modifiers: ShortcutModifierSet(command: true, option: true)),
        title: "Save All"
    ),
    .init(
        binding: ShortcutBinding(key: "p", modifiers: ShortcutModifierSet(command: true, shift: true)),
        title: "Open Command Palette"
    ),
    .init(
        binding: ShortcutBinding(key: "p", modifiers: ShortcutModifierSet(command: true)),
        title: "Open Quickly"
    ),
    .init(
        binding: ShortcutBinding(key: "f", modifiers: ShortcutModifierSet(command: true)),
        title: "Find"
    ),
    .init(
        binding: ShortcutBinding(key: "f", modifiers: ShortcutModifierSet(command: true, shift: true)),
        title: "Find In Files"
    ),
    .init(
        binding: ShortcutBinding(
            key: "n",
            modifiers: ShortcutModifierSet(command: true, control: true, shift: true)
        ),
        title: "Show Notifications"
    ),
]

extension ShortcutBinding {
    var keyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent = keyEquivalent else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    var displayString: String {
        let parts = modifierSymbols + [displayKey]
        return parts.joined()
    }

    var displayKey: String {
        switch normalizedKey {
        case "return":
            "↩"
        case "tab":
            "⇥"
        case "escape":
            "⎋"
        case "space":
            "Space"
        case "delete":
            "⌫"
        case "forwarddelete":
            "⌦"
        case "uparrow":
            "↑"
        case "downarrow":
            "↓"
        case "leftarrow":
            "←"
        case "rightarrow":
            "→"
        default:
            normalizedKey.uppercased()
        }
    }

    static func from(event: NSEvent) -> ShortcutBinding? {
        let modifiers = ShortcutModifierSet(
            command: event.modifierFlags.contains(.command),
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option),
            shift: event.modifierFlags.contains(.shift)
        )
        guard modifiers.command || modifiers.control || modifiers.option || modifiers.shift else {
            return nil
        }

        if let key = shortcutKeyToken(for: event) {
            return ShortcutBinding(key: key, modifiers: modifiers)
        }

        return nil
    }

    private var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if self.modifiers.command {
            modifiers.insert(.command)
        }
        if self.modifiers.control {
            modifiers.insert(.control)
        }
        if self.modifiers.option {
            modifiers.insert(.option)
        }
        if self.modifiers.shift {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    private var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers.control {
            symbols.append("⌃")
        }
        if modifiers.option {
            symbols.append("⌥")
        }
        if modifiers.shift {
            symbols.append("⇧")
        }
        if modifiers.command {
            symbols.append("⌘")
        }
        return symbols
    }

    private var keyEquivalent: KeyEquivalent? {
        switch normalizedKey {
        case "return":
            return .return
        case "tab":
            return .tab
        case "space":
            return .space
        case "escape":
            return .escape
        case "delete":
            return .delete
        case "uparrow":
            return .upArrow
        case "downarrow":
            return .downArrow
        case "leftarrow":
            return .leftArrow
        case "rightarrow":
            return .rightArrow
        default:
            guard normalizedKey.count == 1, let character = normalizedKey.first else {
                return nil
            }
            return KeyEquivalent(character)
        }
    }
}

private func shortcutKeyToken(for event: NSEvent) -> String? {
    switch event.keyCode {
    case 36, 76:
        return "return"
    case 48:
        return "tab"
    case 49:
        return "space"
    case 51:
        return "delete"
    case 53:
        return "escape"
    case 117:
        return "forwarddelete"
    case 123:
        return "leftarrow"
    case 124:
        return "rightarrow"
    case 125:
        return "downarrow"
    case 126:
        return "uparrow"
    default:
        guard let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              characters.count == 1 else {
            return nil
        }
        return characters.lowercased()
    }
}

extension View {
    @ViewBuilder
    func applyingKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
