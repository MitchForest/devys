// Repository.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents a git repository tracked by Devys.
public struct Repository: Identifiable, Codable, Equatable, Hashable, Sendable {
    public typealias ID = String

    /// Stable identifier for this repository.
    /// Uses the standardized repository root path.
    public let id: ID

    /// URL to the repository root.
    public var rootURL: URL

    /// Display name for the repository.
    public var displayName: String

    /// Reference used to look up repository-scoped settings.
    public var settingsReference: String

    /// Creates a new repository record.
    /// - Parameters:
    ///   - rootURL: Repository root URL.
    ///   - displayName: Display name. Defaults to the folder name.
    ///   - settingsReference: Optional settings reference. Defaults to the repository ID.
    public init(
        rootURL: URL,
        displayName: String? = nil,
        settingsReference: String? = nil
    ) {
        let normalizedRootURL = rootURL.standardizedFileURL
        let stableID = normalizedRootURL.path

        self.id = stableID
        self.rootURL = normalizedRootURL
        self.displayName = displayName ?? normalizedRootURL.lastPathComponent
        self.settingsReference = settingsReference ?? stableID
    }
}
