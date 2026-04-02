// CodexThreadService.swift
// Codex thread operations.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

@MainActor
public protocol CodexThreadService {
    func archiveThread(id: String, projectFolder: URL?) async throws
}

@MainActor
public final class DefaultCodexThreadService: CodexThreadService {
    private var agent: DevysAgent?

    public init() {}

    public func archiveThread(id: String, projectFolder: URL?) async throws {
        let agent = try await ensureAgent(projectFolder: projectFolder)
        guard let codex = agent.codex else {
            throw DevysAgentError.unsupportedHarness
        }
        try await codex.archiveThread(id: id)
    }

    private func ensureAgent(projectFolder: URL?) async throws -> DevysAgent {
        if let agent { return try await ensureStarted(agent: agent) }

        let cwd = projectFolder?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let newAgent = await DevysAgent(harnessType: .codex, cwd: cwd)
        self.agent = newAgent
        return try await ensureStarted(agent: newAgent)
    }

    private func ensureStarted(agent: DevysAgent) async throws -> DevysAgent {
        if await agent.codexState != .ready {
            try await agent.start()
        }
        return agent
    }
}
