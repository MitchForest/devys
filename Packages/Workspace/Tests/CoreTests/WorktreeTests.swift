// WorktreeTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import Foundation
@testable import Workspace

@Suite("Worktree Models Tests")
struct WorktreeModelTests {
    @Test("Worktree initialization sets all properties")
    func worktreeInitialization() {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let worktreeURL = URL(fileURLWithPath: "/tmp/repo-wt")
        let worktree = Worktree(
            name: "feature/test",
            detail: "repo-wt",
            workingDirectory: worktreeURL,
            repositoryRootURL: repoURL,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(worktree.id == worktreeURL.path)
        #expect(worktree.name == "feature/test")
        #expect(worktree.detail == "repo-wt")
        #expect(worktree.workingDirectory == worktreeURL)
        #expect(worktree.repositoryRootURL == repoURL)
        #expect(worktree.createdAt == Date(timeIntervalSince1970: 0))
    }

    @Test("Worktree is Codable")
    func worktreeCodable() throws {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let worktreeURL = URL(fileURLWithPath: "/tmp/repo-wt")
        let original = Worktree(
            name: "feature/test",
            detail: "repo-wt",
            workingDirectory: worktreeURL,
            repositoryRootURL: repoURL
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == original.id)
    }

    @Test("WorktreeState is Codable")
    func worktreeStateCodable() throws {
        let state = WorktreeState(
            worktreeId: "/tmp/repo-wt",
            isPinned: true,
            isArchived: false,
            order: 3,
            lastFocused: Date(timeIntervalSince1970: 10)
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorktreeState.self, from: data)

        #expect(decoded == state)
    }
}

@Suite("Worktree Persistence Tests")
struct WorktreePersistenceTests {
    @Test("Worktree persistence round-trip")
    func worktreePersistenceRoundTrip() {
        let suiteName = "com.devys.tests.worktree.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = UserDefaultsWorktreePersistenceService(userDefaults: userDefaults)
        let states = [
            WorktreeState(
                worktreeId: "/tmp/repo-wt",
                isPinned: true,
                isArchived: false,
                order: 1,
                lastFocused: Date(timeIntervalSince1970: 2)
            )
        ]
        let selection = WorktreeSelection(selectedWorktreeId: "/tmp/repo-wt")

        service.saveStates(states)
        service.saveSelection(selection)

        #expect(service.loadStates() == states)
        #expect(service.loadSelection() == selection)
    }
}
