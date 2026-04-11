// GitRepositoryDiscoveryServiceTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Testing
@testable import Workspace

@Suite("Repository Discovery Tests")
struct GitRepositoryDiscoveryServiceTests {
    @Test("Repository discovery resolves the git root from a nested directory")
    func resolveRepositoryRoot() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-repo-discovery-\(UUID().uuidString)")
        let nestedDirectory = temporaryRoot.appendingPathComponent("Sources/App")
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try runGit(arguments: ["init"], workingDirectory: temporaryRoot)

        let service = GitRepositoryDiscoveryService()
        let repository = try await service.resolveRepository(from: nestedDirectory)

        #expect(repository.rootURL == temporaryRoot.standardizedFileURL)
        #expect(repository.id == temporaryRoot.standardizedFileURL.path)
        #expect(repository.sourceControl == .git)
    }

    @Test("Repository discovery accepts plain folders without Git")
    func resolvePlainFolder() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-non-repo-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let service = GitRepositoryDiscoveryService()
        let repository = try await service.resolveRepository(from: temporaryRoot)

        #expect(repository.rootURL == temporaryRoot.standardizedFileURL)
        #expect(repository.id == temporaryRoot.standardizedFileURL.path)
        #expect(repository.sourceControl == .none)
    }

    private func runGit(arguments: [String], workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = workingDirectory
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
