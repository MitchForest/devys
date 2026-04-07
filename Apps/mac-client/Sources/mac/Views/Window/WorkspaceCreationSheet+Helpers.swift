// WorkspaceCreationSheet+Helpers.swift
// Secondary helpers for workspace creation flows.
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import Git
import Workspace

@MainActor
extension WorkspaceCreationSheet {
    func resolvedPullRequest() async throws -> PullRequest {
        let trimmedReference = pullRequestReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReference.isEmpty {
            let number = try creationService.parsePullRequestNumber(from: trimmedReference)
            return try await creationService.pullRequest(number: number, in: repository.rootURL)
        }

        if let selectedPullRequest {
            return selectedPullRequest
        }

        throw WorkspaceCreationError.invalidPullRequestReference(pullRequestReference)
    }

    func destinationPath(for branchName: String) -> String {
        creationService
            .suggestedWorktreeLocation(forBranchNamed: branchName, in: repository)
            .path
    }

    func selectImportedWorktrees() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose worktree directories to import"
        panel.prompt = "Import Worktrees"

        guard panel.runModal() == .OK else { return }
        importedWorktreeURLs = panel.urls.map(\.standardizedFileURL)
    }
}
