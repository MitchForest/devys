// RecentRepositoriesService.swift
// Service for persisting and retrieving recently opened repositories.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
public final class RecentRepositoriesService {
    private let key = "com.devys.recentRepositories"
    private let maxCount = 20
    private let fileManager = FileManager.default
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func add(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        var recent = load()
        recent.removeAll { $0.standardizedFileURL == normalizedURL }
        recent.insert(normalizedURL, at: 0)

        if recent.count > maxCount {
            recent = Array(recent.prefix(maxCount))
        }

        save(recent)
    }

    public func remove(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        var recent = load()
        recent.removeAll { $0.standardizedFileURL == normalizedURL }
        save(recent)
    }

    public func load() -> [URL] {
        guard let data = userDefaults.data(forKey: key),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return paths.compactMap { path -> URL? in
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            return nil
        }
    }

    public func clear() {
        userDefaults.removeObject(forKey: key)
    }

    private func save(_ urls: [URL]) {
        let paths = urls.map(\.path)
        if let data = try? JSONEncoder().encode(paths) {
            userDefaults.set(data, forKey: key)
        }
    }
}
