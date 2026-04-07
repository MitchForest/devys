// RecentRepositoriesServiceTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Testing
@testable import Workspace

@Suite("Recent Repositories Service Tests")
struct RecentRepositoriesServiceTests {
    @Test("Recent repositories preserve recency and uniqueness")
    @MainActor
    func recencyAndUniqueness() {
        let suiteName = "com.devys.tests.recent-repositories.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = RecentRepositoriesService(userDefaults: userDefaults)
        let first = URL(fileURLWithPath: "/tmp/repo-a")
        let second = URL(fileURLWithPath: "/tmp/repo-b")

        FileManager.default.createFile(atPath: first.path, contents: nil)
        FileManager.default.createFile(atPath: second.path, contents: nil)
        try? FileManager.default.removeItem(at: first)
        try? FileManager.default.removeItem(at: second)
        try? FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        service.add(first)
        service.add(second)
        service.add(first)

        #expect(service.load() == [first.standardizedFileURL, second.standardizedFileURL])
    }
}
