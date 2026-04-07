// TerminalHostModels.swift
// Devys - Persistent terminal host models and relaunch snapshots.

import Foundation
import Workspace

struct HostedTerminalSessionRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let workspaceID: Workspace.ID
    let workingDirectory: URL?
    let launchCommand: String?
    let processID: Int32?
    let createdAt: Date

    init(
        id: UUID,
        workspaceID: Workspace.ID,
        workingDirectory: URL?,
        launchCommand: String?,
        processID: Int32? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.workingDirectory = workingDirectory
        self.launchCommand = launchCommand
        self.processID = processID
        self.createdAt = createdAt
    }
}

enum PersistedWorkspaceTabRecord: Codable, Equatable, Sendable {
    case terminal(hostedSessionID: UUID)
    case editor(fileURL: URL)
    case gitDiff(path: String, isStaged: Bool)

    private enum CodingKeys: String, CodingKey {
        case kind
        case hostedSessionID
        case fileURL
        case path
        case isStaged
    }

    private enum Kind: String, Codable {
        case terminal
        case editor
        case gitDiff
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .terminal:
            self = .terminal(
                hostedSessionID: try container.decode(UUID.self, forKey: .hostedSessionID)
            )
        case .editor:
            self = .editor(
                fileURL: try container.decode(URL.self, forKey: .fileURL)
            )
        case .gitDiff:
            self = .gitDiff(
                path: try container.decode(String.self, forKey: .path),
                isStaged: try container.decode(Bool.self, forKey: .isStaged)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let hostedSessionID):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(hostedSessionID, forKey: .hostedSessionID)
        case .editor(let fileURL):
            try container.encode(Kind.editor, forKey: .kind)
            try container.encode(fileURL, forKey: .fileURL)
        case .gitDiff(let path, let isStaged):
            try container.encode(Kind.gitDiff, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(isStaged, forKey: .isStaged)
        }
    }
}

indirect enum PersistedWorkspaceLayoutTree: Codable, Equatable, Sendable {
    case pane(selectedTabIndex: Int?, tabs: [PersistedWorkspaceTabRecord])
    case split(
        orientation: String,
        dividerPosition: Double,
        first: PersistedWorkspaceLayoutTree,
        second: PersistedWorkspaceLayoutTree
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case selectedTabIndex
        case tabs
        case orientation
        case dividerPosition
        case first
        case second
    }

    private enum Kind: String, Codable {
        case pane
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pane:
            self = .pane(
                selectedTabIndex: try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex),
                tabs: try container.decode([PersistedWorkspaceTabRecord].self, forKey: .tabs)
            )
        case .split:
            self = .split(
                orientation: try container.decode(String.self, forKey: .orientation),
                dividerPosition: try container.decode(Double.self, forKey: .dividerPosition),
                first: try container.decode(PersistedWorkspaceLayoutTree.self, forKey: .first),
                second: try container.decode(PersistedWorkspaceLayoutTree.self, forKey: .second)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let selectedTabIndex, let tabs):
            try container.encode(Kind.pane, forKey: .kind)
            try container.encodeIfPresent(selectedTabIndex, forKey: .selectedTabIndex)
            try container.encode(tabs, forKey: .tabs)
        case .split(let orientation, let dividerPosition, let first, let second):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(orientation, forKey: .orientation)
            try container.encode(dividerPosition, forKey: .dividerPosition)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }
}

struct PersistedWorkspaceLayoutState: Codable, Equatable, Sendable, Identifiable {
    let workspaceID: Workspace.ID
    let sidebarMode: WorkspaceSidebarMode
    let tree: PersistedWorkspaceLayoutTree

    var id: Workspace.ID {
        workspaceID
    }
}

struct TerminalRelaunchSnapshot: Codable, Sendable {
    var repositoryRootURLs: [URL]
    var selectedRepositoryID: Repository.ID?
    var selectedWorkspaceID: Workspace.ID?
    var hostedSessions: [HostedTerminalSessionRecord]
    var workspaceStates: [PersistedWorkspaceLayoutState]

    var hasRepositories: Bool {
        !repositoryRootURLs.isEmpty
    }

    static let empty = TerminalRelaunchSnapshot(
        repositoryRootURLs: [],
        selectedRepositoryID: nil,
        selectedWorkspaceID: nil,
        hostedSessions: [],
        workspaceStates: []
    )

    static func == (lhs: TerminalRelaunchSnapshot, rhs: TerminalRelaunchSnapshot) -> Bool {
        lhs.repositoryRootURLs == rhs.repositoryRootURLs
            && lhs.selectedRepositoryID == rhs.selectedRepositoryID
            && lhs.selectedWorkspaceID == rhs.selectedWorkspaceID
            && lhs.hostedSessions == rhs.hostedSessions
            && lhs.workspaceStates == rhs.workspaceStates
    }
}
