// Repository.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents a git repository tracked by Devys.
public struct Repository: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this repository.
    public let id: UUID

    /// URL to the repository root.
    public var rootURL: URL

    /// Display name for the repository.
    public var name: String

    /// Last time this repository was opened.
    public var lastOpened: Date?

    /// Creates a new repository record.
    /// - Parameters:
    ///   - rootURL: Repository root URL.
    ///   - name: Display name. Defaults to the folder name.
    ///   - lastOpened: Last opened date.
    ///   - id: Unique identifier.
    public init(
        rootURL: URL,
        name: String? = nil,
        lastOpened: Date? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.rootURL = rootURL
        self.name = name ?? rootURL.lastPathComponent
        self.lastOpened = lastOpened
    }
}
