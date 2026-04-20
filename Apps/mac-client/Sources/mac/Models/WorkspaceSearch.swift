// WorkspaceSearch.swift
// Workspace search request, item, and action modeling.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import Workspace
import Editor

enum WorkspaceCommandPaletteAction: Equatable {
    case addRepository
    case selectRepository(Repository.ID)
    case initializeRepository(Repository.ID)
    case createWorkspace(Repository.ID)
    case importWorktrees(Repository.ID)
    case selectWorkspace(repositoryID: Repository.ID, workspaceID: Workspace.ID)
    case openChat
    case focusChatSession(ChatSessionID)
    case createWorkflow
    case openWorkflowDefinition(String)
    case openWorkflowRun(UUID)
    case launchShell
    case launchClaude
    case launchCodex
    case runDefaultProfile
    case jumpToLatestUnreadWorkspace
    case revealCurrentWorkspaceInNavigator
}

enum WorkspaceSearchMode: String, Identifiable, Sendable {
    case commands
    case files
    case textSearch

    var id: String {
        rawValue
    }

    var placeholder: String {
        switch self {
        case .commands:
            "Search commands"
        case .files:
            "Search files"
        case .textSearch:
            "Search in files"
        }
    }

    var emptyTitle: String {
        switch self {
        case .commands:
            "No matching commands"
        case .files:
            "No matching files"
        case .textSearch:
            "No matching results"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .commands:
            "Try a repository, workspace, launch action, or unread command."
        case .files:
            "Try a filename, folder name, or path segment."
        case .textSearch:
            "Type a search term to scan the active workspace."
        }
    }
}

struct WorkspaceSearchRequest: Identifiable, Equatable {
    let mode: WorkspaceSearchMode
    let initialQuery: String
    let token: UUID

    init(
        mode: WorkspaceSearchMode,
        initialQuery: String = "",
        token: UUID = UUID()
    ) {
        self.mode = mode
        self.initialQuery = initialQuery
        self.token = token
    }

    var id: String {
        "\(mode.rawValue)|\(token.uuidString)"
    }
}

struct WorkspaceTextSearchMatch: Identifiable, Equatable, Sendable {
    let workspaceID: Workspace.ID
    let fileURL: URL
    let relativePath: String
    let lineNumber: Int
    let columnNumber: Int
    let preview: String
    let match: EditorSearchMatch

    var id: String {
        "\(fileURL.path)#\(lineNumber):\(columnNumber):\(match.id)"
    }
}

enum WorkspaceSearchAction: Equatable {
    case command(WorkspaceCommandPaletteAction)
    case openFile(workspaceID: Workspace.ID, url: URL)
    case openTextSearchMatch(WorkspaceTextSearchMatch)
}

struct WorkspaceSearchItem: Identifiable, Equatable {
    let action: WorkspaceSearchAction
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]
    let accessory: String?

    var id: String {
        switch action {
        case .command(let command):
            switch command {
            case .addRepository:
                "command:add-repository"
            case .selectRepository(let repositoryID):
                "command:select-repository:\(repositoryID)"
            case .initializeRepository(let repositoryID):
                "command:initialize-repository:\(repositoryID)"
            case .createWorkspace(let repositoryID):
                "command:create-workspace:\(repositoryID)"
            case .importWorktrees(let repositoryID):
                "command:import-worktrees:\(repositoryID)"
            case .selectWorkspace(let repositoryID, let workspaceID):
                "command:select-workspace:\(repositoryID):\(workspaceID)"
            case .openChat:
                "command:open-chat"
            case .focusChatSession(let sessionID):
                "command:focus-chat-session:\(sessionID.rawValue)"
            case .createWorkflow:
                "command:create-workflow"
            case .openWorkflowDefinition(let definitionID):
                "command:open-workflow-definition:\(definitionID)"
            case .openWorkflowRun(let runID):
                "command:open-workflow-run:\(runID.uuidString)"
            case .launchShell:
                "command:launch-shell"
            case .launchClaude:
                "command:launch-claude"
            case .launchCodex:
                "command:launch-codex"
            case .runDefaultProfile:
                "command:run-default-profile"
            case .jumpToLatestUnreadWorkspace:
                "command:jump-latest-unread-workspace"
            case .revealCurrentWorkspaceInNavigator:
                "command:reveal-current-workspace"
            }
        case .openFile(let workspaceID, let url):
            "file:\(workspaceID):\(url.standardizedFileURL.path)"
        case .openTextSearchMatch(let match):
            "text:\(match.id)"
        }
    }
}
