// Repository.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Source-control capability tracked for a project root.
public enum RepositorySourceControl: String, Codable, Equatable, Hashable, Sendable {
    case none
    case git
}

/// Represents a project root tracked by Devys.
public struct Repository: Identifiable, Codable, Equatable, Hashable, Sendable {
    public typealias ID = String

    /// Stable identifier for this project root.
    /// Uses the standardized root path.
    public let id: ID

    /// URL to the project root.
    public var rootURL: URL

    /// Display name for the project.
    public var displayName: String

    /// Reference used to look up project-scoped settings.
    public var settingsReference: String

    /// Current source-control capability for the project root.
    public var sourceControl: RepositorySourceControl

    /// Custom 2-letter initials override for the repo rail tile.
    /// When nil, auto-derived from `displayName`.
    public var displayInitials: String?

    /// SF Symbol name for the repo rail tile.
    /// When set, renders a symbol instead of initials.
    public var displaySymbol: String?

    /// Whether the project root is currently backed by Git.
    public var isGitRepository: Bool {
        sourceControl == .git
    }

    /// Creates a new project record.
    /// - Parameters:
    ///   - rootURL: Project root URL.
    ///   - displayName: Display name. Defaults to the folder name.
    ///   - settingsReference: Optional settings reference. Defaults to the repository ID.
    ///   - sourceControl: Current source-control capability. Defaults to `.none`.
    public init(
        rootURL: URL,
        displayName: String? = nil,
        settingsReference: String? = nil,
        sourceControl: RepositorySourceControl = .none
    ) {
        let normalizedRootURL = rootURL.standardizedFileURL
        let stableID = normalizedRootURL.path

        self.id = stableID
        self.rootURL = normalizedRootURL
        self.displayName = displayName ?? normalizedRootURL.lastPathComponent
        self.settingsReference = settingsReference ?? stableID
        self.sourceControl = sourceControl
        self.displayInitials = nil
        self.displaySymbol = nil
    }

    /// Creates a new project record with custom rail display options.
    public init(
        rootURL: URL,
        displayName: String? = nil,
        settingsReference: String? = nil,
        sourceControl: RepositorySourceControl = .none,
        displayInitials: String?,
        displaySymbol: String?
    ) {
        let normalizedRootURL = rootURL.standardizedFileURL
        let stableID = normalizedRootURL.path

        self.id = stableID
        self.rootURL = normalizedRootURL
        self.displayName = displayName ?? normalizedRootURL.lastPathComponent
        self.settingsReference = settingsReference ?? stableID
        self.sourceControl = sourceControl
        self.displayInitials = displayInitials
        self.displaySymbol = displaySymbol
    }
}
