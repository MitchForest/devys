// WorkspaceCreationServiceTests.swift
// GitTests

import Foundation
import Testing
@testable import Git
import Workspace

@Suite("Workspace Creation Service Tests")
struct WorkspaceCreationServiceTests {
    @Test("Create workspace from a new branch")
    func createWorkspaceFromNewBranch() async throws {
        let fixture = try TestRepositoryFixture()
        defer { fixture.cleanup() }

        let repository = Repository(rootURL: fixture.repositoryRoot)
        let service = WorkspaceCreationService()

        let workspace = try await service.createWorkspace(
            in: repository,
            request: .newBranch(name: "feature/new-workspace", baseReference: "main")
        )
        defer {
            try? FileManager.default.removeItem(at: workspace.worktreeURL)
        }

        #expect(workspace.branchName == "feature/new-workspace")
        #expect(workspace.kind == .branch)
        #expect(FileManager.default.fileExists(atPath: workspace.worktreeURL.path))

        let branchName = try await currentBranch(at: workspace.worktreeURL)
        #expect(branchName == "feature/new-workspace")
    }

    @Test("Create workspace from an existing local branch")
    func createWorkspaceFromExistingBranch() async throws {
        let fixture = try TestRepositoryFixture()
        defer { fixture.cleanup() }

        try fixture.runGit(arguments: ["branch", "feature/existing"])

        let repository = Repository(rootURL: fixture.repositoryRoot)
        let service = WorkspaceCreationService()

        let workspace = try await service.createWorkspace(
            in: repository,
            request: .existingBranch(
                WorkspaceBranchReference(
                    name: "feature/existing",
                    displayName: "feature/existing",
                    isRemote: false,
                    isCurrent: false
                )
            )
        )
        defer {
            try? FileManager.default.removeItem(at: workspace.worktreeURL)
        }

        #expect(workspace.branchName == "feature/existing")
        #expect(workspace.kind == .branch)
        #expect(try await currentBranch(at: workspace.worktreeURL) == "feature/existing")
    }

    @Test("Import existing worktrees from the same repository")
    func importExistingWorktree() async throws {
        let fixture = try TestRepositoryFixture()
        defer { fixture.cleanup() }

        let importedURL = fixture.repositoryRoot.deletingLastPathComponent()
            .appendingPathComponent("Devys-imported")
        try fixture.runGit(arguments: [
            "worktree", "add",
            "-b", "feature/imported",
            importedURL.path,
            "main"
        ])
        defer {
            try? FileManager.default.removeItem(at: importedURL)
        }

        let repository = Repository(rootURL: fixture.repositoryRoot)
        let service = WorkspaceCreationService()

        let workspaces = try await service.importWorkspaces(
            at: [importedURL],
            into: repository
        )

        #expect(workspaces.count == 1)
        #expect(workspaces[0].branchName == "feature/imported")
        #expect(workspaces[0].kind == .imported)
    }

    @Test("Parse pull request numbers from raw values and URLs")
    func parsePullRequestNumbers() throws {
        let service = WorkspaceCreationService()

        #expect(try service.parsePullRequestNumber(from: "42") == 42)
        #expect(
            try service.parsePullRequestNumber(from: "https://github.com/devys/devys/pull/73") == 73
        )
    }

    private func currentBranch(at url: URL) async throws -> String {
        let client = GitClient(repositoryURL: url)
        return try await client.getCurrentBranch()
    }
}

private struct TestRepositoryFixture {
    let repositoryRoot: URL

    init() throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        try runGit(arguments: ["init", "-b", "main"])
        try runGit(arguments: ["config", "user.name", "Devys Tests"])
        try runGit(arguments: ["config", "user.email", "tests@devys.local"])

        let readmeURL = repositoryRoot.appendingPathComponent("README.md")
        try "devys\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try runGit(arguments: ["add", "README.md"])
        try runGit(arguments: ["commit", "-m", "Initial commit"])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func runGit(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
