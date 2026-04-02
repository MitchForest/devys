// WorktreePersistenceService.swift
// Worktree persistence abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public protocol WorktreePersistenceService {
    func loadStates() -> [WorktreeState]
    func saveStates(_ states: [WorktreeState])

    func loadSelection() -> WorktreeSelection
    func saveSelection(_ selection: WorktreeSelection)
}

public struct UserDefaultsWorktreePersistenceService: WorktreePersistenceService {
    private enum Keys {
        static let states = "com.devys.worktrees.state"
        static let selection = "com.devys.worktrees.selection"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadStates() -> [WorktreeState] {
        load(key: Keys.states) ?? []
    }

    public func saveStates(_ states: [WorktreeState]) {
        save(states, key: Keys.states)
    }

    public func loadSelection() -> WorktreeSelection {
        load(key: Keys.selection) ?? WorktreeSelection.empty
    }

    public func saveSelection(_ selection: WorktreeSelection) {
        save(selection, key: Keys.selection)
    }

    private func save<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func load<T: Codable>(key: String) -> T? {
        guard let data = userDefaults.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return value
    }
}
