// RepositoryPersistenceService.swift
// Repository persistence abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public protocol RepositoryPersistenceService: Sendable {
    func loadRepositories() -> [Repository]
    func saveRepositories(_ repositories: [Repository])
}

public struct UserDefaultsRepositoryPersistenceService: RepositoryPersistenceService, @unchecked Sendable {
    private enum Keys {
        static let repositories = "com.devys.repositories"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadRepositories() -> [Repository] {
        load(key: Keys.repositories) ?? []
    }

    public func saveRepositories(_ repositories: [Repository]) {
        save(repositories, key: Keys.repositories)
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
