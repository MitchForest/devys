// WindowState.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import Workspace

/// Per-window state for managing imported repositories and the selected workspace.
///
/// Each window has its own WindowState instance.
/// - Zero or more repositories per window
/// - Zero or one selected workspace per window
@MainActor
@Observable
public final class WindowState {
    // MARK: - Properties

    /// Imported repositories for this window.
    public private(set) var repositories: [Repository]

    /// The currently selected repository.
    public private(set) var selectedRepositoryID: Repository.ID?

    /// The currently selected workspace.
    public private(set) var selectedWorkspaceID: Workspace.ID?

    // MARK: - Computed Properties

    /// Whether any repositories are open.
    public var hasRepositories: Bool {
        !repositories.isEmpty
    }

    public var selectedRepository: Repository? {
        guard let selectedRepositoryID else { return nil }
        return repositories.first { $0.id == selectedRepositoryID }
    }

    public var selectedRepositoryRootURL: URL? {
        selectedRepository?.rootURL
    }
    
    // MARK: - Initialization

    public init(
        repositories: [Repository] = [],
        selectedRepositoryID: Repository.ID? = nil,
        selectedWorkspaceID: Workspace.ID? = nil
    ) {
        self.repositories = repositories
        self.selectedRepositoryID = selectedRepositoryID
        self.selectedWorkspaceID = selectedWorkspaceID
        normalizeSelection()
    }

    // MARK: - Repository Operations

    public func importRepository(_ repository: Repository) {
        if let existingIndex = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[existingIndex] = repository
        } else {
            repositories.append(repository)
        }

        selectedRepositoryID = repository.id
        selectedWorkspaceID = nil
        normalizeSelection()
    }

    public func openRepository(_ url: URL) {
        importRepository(Repository(rootURL: url))
    }

    public func selectRepository(_ repositoryID: Repository.ID?) {
        selectedRepositoryID = repositoryID
        selectedWorkspaceID = nil
        normalizeSelection()
    }

    public func selectWorkspace(_ workspaceID: Workspace.ID?) {
        selectedWorkspaceID = workspaceID
    }

    public func restoreSelection(
        repositoryID: Repository.ID?,
        workspaceID: Workspace.ID?
    ) {
        selectedRepositoryID = repositoryID
        selectedWorkspaceID = nil
        normalizeSelection()

        guard selectedRepositoryID != nil else { return }
        selectedWorkspaceID = workspaceID
    }

    private func normalizeSelection() {
        guard !repositories.isEmpty else {
            selectedRepositoryID = nil
            selectedWorkspaceID = nil
            return
        }

        if let selectedRepositoryID,
           repositories.contains(where: { $0.id == selectedRepositoryID }) {
            return
        }

        selectedRepositoryID = repositories.last?.id
        selectedWorkspaceID = nil
    }
}
