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
            lastFocused: Date(timeIntervalSince1970: 10),
            displayNameOverride: "Focused Worktree"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorktreeState.self, from: data)

        #expect(decoded == state)
    }

    @Test("Primary worktree is identified by matching repository root")
    func primaryWorktree() {
        let repositoryURL = URL(fileURLWithPath: "/tmp/repo")
        let primary = Worktree(
            workingDirectory: repositoryURL,
            repositoryRootURL: repositoryURL
        )
        let secondary = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo-feature"),
            repositoryRootURL: repositoryURL
        )

        #expect(primary.isPrimary)
        #expect(!secondary.isPrimary)
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

@Suite("Worktree Manager Tests")
struct WorktreeManagerTests {
    @Test("Worktree manager preserves state across repository refreshes")
    @MainActor
    func preserveStateAcrossRepositories() async {
        let repositoryA = URL(fileURLWithPath: "/tmp/repo-a")
        let repositoryB = URL(fileURLWithPath: "/tmp/repo-b")
        let worktreeA = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo-a-feature"),
            repositoryRootURL: repositoryA,
            name: "feature/a"
        )
        let worktreeB = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo-b-feature"),
            repositoryRootURL: repositoryB,
            name: "feature/b"
        )

        let manager = WorktreeManager(
            persistenceService: InMemoryWorktreePersistenceService(),
            listingService: StubWorktreeListingService(
                worktreesByRepositoryRoot: [
                    repositoryA.path: [worktreeA],
                    repositoryB.path: [worktreeB]
                ]
            )
        )

        await manager.refresh(for: repositoryA)
        manager.setPinned(worktreeA.id, isPinned: true)
        manager.setDisplayNameOverride("Workspace A", for: worktreeA.id)

        await manager.refresh(for: repositoryB)

        #expect(manager.state(for: worktreeA.id)?.isPinned == true)
        #expect(manager.state(for: worktreeA.id)?.displayNameOverride == "Workspace A")
        #expect(manager.state(for: worktreeB.id) != nil)
    }

    @Test("Archived worktrees are hidden from visible ordering and remain separately addressable")
    @MainActor
    func archivedFiltering() async {
        let repositoryRoot = URL(fileURLWithPath: "/tmp/repo")
        let visible = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo-visible"),
            repositoryRootURL: repositoryRoot,
            name: "visible"
        )
        let archived = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/repo-archived"),
            repositoryRootURL: repositoryRoot,
            name: "archived"
        )

        let manager = WorktreeManager(
            persistenceService: InMemoryWorktreePersistenceService(),
            listingService: StubWorktreeListingService(
                worktreesByRepositoryRoot: [repositoryRoot.path: [visible, archived]]
            )
        )

        await manager.refresh(for: repositoryRoot)
        manager.setArchived(archived.id, isArchived: true)

        #expect(manager.visibleWorktrees(from: [visible, archived]).map(\.id) == [visible.id])
        #expect(manager.archivedWorktrees(from: [visible, archived]).map(\.id) == [archived.id])
    }

    @Test("Navigator ordering stays responsive with ten repositories and one hundred workspaces")
    @MainActor
    func navigatorOrderingAtScale() {
        let repositoryRoots = (0..<10).map { index in
            URL(fileURLWithPath: "/tmp/devys-repo-\(index)")
        }
        let worktrees = repositoryRoots.flatMap { repositoryRoot in
            (0..<10).map { index in
                Worktree(
                    workingDirectory: URL(
                        fileURLWithPath: "\(repositoryRoot.path)-workspace-\(index)"
                    ),
                    repositoryRootURL: repositoryRoot,
                    name: "feature/\(index)"
                )
            }
        }
        let states = worktrees.enumerated().map { index, worktree in
            WorktreeState(
                worktreeId: worktree.id,
                isPinned: index.isMultiple(of: 15),
                isArchived: index.isMultiple(of: 10),
                order: index % 10,
                lastFocused: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let manager = WorktreeManager(
            persistenceService: InMemoryWorktreePersistenceService(states: states),
            listingService: StubWorktreeListingService(worktreesByRepositoryRoot: [:])
        )
        let worktreesByRepository = Dictionary(grouping: worktrees, by: \.repositoryRootURL.path)
        let clock = ContinuousClock()
        let start = clock.now
        var visibleCount = 0
        var archivedCount = 0

        for _ in 0..<200 {
            for repositoryRoot in repositoryRoots {
                let slice = worktreesByRepository[repositoryRoot.path] ?? []
                visibleCount += manager.visibleWorktrees(from: slice).count
                archivedCount += manager.archivedWorktrees(from: slice).count
            }
        }

        let elapsed = start.duration(to: clock.now)

        #expect(visibleCount == 18_000)
        #expect(archivedCount == 2_000)
        #expect(elapsed < .seconds(1))
    }
}

private final class InMemoryWorktreePersistenceService: WorktreePersistenceService, @unchecked Sendable {
    private var storedStates: [WorktreeState] = []
    private var storedSelection = WorktreeSelection.empty

    init(
        states: [WorktreeState] = [],
        selection: WorktreeSelection = .empty
    ) {
        self.storedStates = states
        self.storedSelection = selection
    }

    func loadStates() -> [WorktreeState] {
        storedStates
    }

    func saveStates(_ states: [WorktreeState]) {
        storedStates = states
    }

    func loadSelection() -> WorktreeSelection {
        storedSelection
    }

    func saveSelection(_ selection: WorktreeSelection) {
        storedSelection = selection
    }
}

private struct StubWorktreeListingService: WorktreeListingService {
    let worktreesByRepositoryRoot: [String: [Worktree]]

    func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree] {
        worktreesByRepositoryRoot[repositoryRoot.path] ?? []
    }
}
