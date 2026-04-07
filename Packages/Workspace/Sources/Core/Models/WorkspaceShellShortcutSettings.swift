// WorkspaceShellShortcutSettings.swift
// Explicit user-editable shortcut bindings for workspace shell actions.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public enum WorkspaceShellShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case nextWorkspace
    case previousWorkspace
    case toggleSidebar
    case toggleNavigator
    case launchShell
    case launchClaude
    case launchCodex
    case jumpToLatestUnreadWorkspace

    public var id: String {
        rawValue
    }
}

public struct ShortcutModifierSet: Codable, Equatable, Hashable, Sendable {
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool

    public init(
        command: Bool = false,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false
    ) {
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
    }
}

public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: ShortcutModifierSet

    public init(key: String, modifiers: ShortcutModifierSet) {
        self.key = ShortcutBinding.normalizeKey(key)
        self.modifiers = modifiers
    }

    public var normalizedKey: String {
        Self.normalizeKey(key)
    }

    public static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct WorkspaceShellShortcutSettings: Codable, Equatable, Sendable {
    public var bindingsByAction: [WorkspaceShellShortcutAction: ShortcutBinding]

    public init(
        bindingsByAction: [WorkspaceShellShortcutAction: ShortcutBinding] = Self.defaultBindings
    ) {
        self.bindingsByAction = bindingsByAction.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = ShortcutBinding(
                key: entry.value.normalizedKey,
                modifiers: entry.value.modifiers
            )
        }
    }

    public func binding(for action: WorkspaceShellShortcutAction) -> ShortcutBinding {
        bindingsByAction[action] ?? Self.defaultBinding(for: action)
    }

    public mutating func setBinding(
        _ binding: ShortcutBinding,
        for action: WorkspaceShellShortcutAction
    ) {
        bindingsByAction[action] = ShortcutBinding(
            key: binding.normalizedKey,
            modifiers: binding.modifiers
        )
    }

    public mutating func restoreDefaults() {
        bindingsByAction = Self.defaultBindings
    }

    public static func defaultBinding(for action: WorkspaceShellShortcutAction) -> ShortcutBinding {
        guard let binding = defaultBindings[action] else {
            fatalError("Missing default binding for \(action.rawValue)")
        }
        return binding
    }

    public static let defaultBindings: [WorkspaceShellShortcutAction: ShortcutBinding] = [
        .nextWorkspace: ShortcutBinding(
            key: "]",
            modifiers: ShortcutModifierSet(command: true, control: true)
        ),
        .previousWorkspace: ShortcutBinding(
            key: "[",
            modifiers: ShortcutModifierSet(command: true, control: true)
        ),
        .toggleSidebar: ShortcutBinding(
            key: "\\",
            modifiers: ShortcutModifierSet(command: true)
        ),
        .toggleNavigator: ShortcutBinding(
            key: "0",
            modifiers: ShortcutModifierSet(command: true)
        ),
        .launchShell: ShortcutBinding(
            key: "return",
            modifiers: ShortcutModifierSet(command: true, control: true)
        ),
        .launchClaude: ShortcutBinding(
            key: "c",
            modifiers: ShortcutModifierSet(command: true, control: true)
        ),
        .launchCodex: ShortcutBinding(
            key: "x",
            modifiers: ShortcutModifierSet(command: true, control: true)
        ),
        .jumpToLatestUnreadWorkspace: ShortcutBinding(
            key: "u",
            modifiers: ShortcutModifierSet(command: true, shift: true)
        ),
    ]
}
