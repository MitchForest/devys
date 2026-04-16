// WorkspaceCatalogPersistenceService.swift
// Workspace list persistence abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public protocol WorkspaceCatalogPersistenceService: Sendable {
    func loadWorkspaces() -> [Workspace]
    func saveWorkspaces(_ workspaces: [Workspace])
}

public struct UserDefaultsWorkspaceCatalogPersistenceService:
    WorkspaceCatalogPersistenceService,
    @unchecked Sendable {
    private enum Keys {
        static let workspaces = "com.devys.workspaces.catalog"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadWorkspaces() -> [Workspace] {
        load(key: Keys.workspaces) ?? []
    }

    public func saveWorkspaces(_ workspaces: [Workspace]) {
        save(workspaces, key: Keys.workspaces)
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
