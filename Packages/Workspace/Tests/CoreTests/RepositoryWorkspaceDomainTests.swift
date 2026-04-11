// RepositoryWorkspaceDomainTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Testing
@testable import Workspace

@Suite("Repository Domain Tests")
struct RepositoryDomainTests {
    @Test("Repository uses a stable path-based identity")
    func repositoryStableIdentity() {
        let repository = Repository(
            rootURL: URL(fileURLWithPath: "/tmp/devys/../devys/repo"),
            displayName: "Devys"
        )

        #expect(repository.id == "/tmp/devys/repo")
        #expect(repository.rootURL.path == "/tmp/devys/repo")
        #expect(repository.displayName == "Devys")
        #expect(repository.settingsReference == repository.id)
        #expect(repository.sourceControl == .none)
    }

    @Test("Repository is Codable")
    func repositoryCodable() throws {
        let original = Repository(
            rootURL: URL(fileURLWithPath: "/tmp/devys/repo"),
            displayName: "Devys",
            settingsReference: "repo-settings",
            sourceControl: .git
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Repository.self, from: data)

        #expect(decoded == original)
    }
}

@Suite("Workspace Domain Tests")
struct WorkspaceDomainTests {
    @Test("Workspace uses a stable path-based identity")
    func workspaceStableIdentity() {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/repo"))
        let workspace = Workspace(
            repositoryID: repository.id,
            branchName: "feature/workspaces",
            worktreeURL: URL(fileURLWithPath: "/tmp/devys/repo/../repo-feature"),
            kind: .pullRequest
        )

        #expect(workspace.id == "/tmp/devys/repo-feature")
        #expect(workspace.repositoryID == repository.id)
        #expect(workspace.branchName == "feature/workspaces")
        #expect(workspace.worktreeURL.path == "/tmp/devys/repo-feature")
        #expect(workspace.kind == .pullRequest)
    }

    @Test("Workspace is Codable")
    func workspaceCodable() throws {
        let original = Workspace(
            repositoryID: "/tmp/devys/repo",
            branchName: "main",
            worktreeURL: URL(fileURLWithPath: "/tmp/devys/repo"),
            kind: .branch
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)

        #expect(decoded == original)
    }
}

@Suite("Repository and Workspace Persistence Tests")
struct RepositoryWorkspacePersistenceTests {
    @Test("Repository persistence round-trip")
    func repositoryPersistenceRoundTrip() {
        let suiteName = "com.devys.tests.repository.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = UserDefaultsRepositoryPersistenceService(userDefaults: userDefaults)
        let repositories = [
            Repository(
                rootURL: URL(fileURLWithPath: "/tmp/devys/repo"),
                displayName: "Devys"
            )
        ]

        service.saveRepositories(repositories)

        #expect(service.loadRepositories() == repositories)
    }

    @Test("Workspace catalog persistence round-trip")
    func workspaceCatalogPersistenceRoundTrip() {
        let suiteName = "com.devys.tests.workspace-catalog.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = UserDefaultsWorkspaceCatalogPersistenceService(userDefaults: userDefaults)
        let workspaces = [
            Workspace(
                repositoryID: "/tmp/devys/repo",
                branchName: "main",
                worktreeURL: URL(fileURLWithPath: "/tmp/devys/repo"),
                kind: .branch
            )
        ]

        service.saveWorkspaces(workspaces)

        #expect(service.loadWorkspaces() == workspaces)
    }
}
