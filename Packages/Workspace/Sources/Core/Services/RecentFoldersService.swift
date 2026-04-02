// RecentFoldersService.swift
// Service for persisting and retrieving recently opened folders.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation

@MainActor
@Observable
public final class RecentFoldersService {
    private let key = "com.devys.recentFolders"
    private let maxCount = 20
    private let fileManager = FileManager.default

    public init() {}

    public func add(_ url: URL) {
        var recent = load()
        recent.removeAll { $0 == url }
        recent.insert(url, at: 0)

        if recent.count > maxCount {
            recent = Array(recent.prefix(maxCount))
        }

        save(recent)
    }

    public func remove(_ url: URL) {
        var recent = load()
        recent.removeAll { $0 == url }
        save(recent)
    }

    public func load() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return paths.compactMap { path -> URL? in
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
    }

    public func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
