// DragDropTypes.swift
// DevysCore - Shared drag and drop types for cross-package communication.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Custom UTTypes for Devys Drag & Drop

public extension UTType {
    /// Custom UTType for git diff attachments in drag and drop.
    /// Format: JSON-encoded GitDiffTransfer
    static let devysGitDiff = UTType(exportedAs: "com.devys.git-diff")
    
    /// Custom UTType for chat items in drag and drop.
    /// Format: UUID string of the chat item
    static let devysChatItem = UTType(exportedAs: "com.devys.chat-item")
}

// MARK: - Git Diff Transfer

/// Transferable data for git diff drag and drop operations.
///
/// Used when dragging a file from the git sidebar to the chat composer.
/// Contains the file path and whether the diff is from staged or unstaged changes.
public struct GitDiffTransfer: Codable, Sendable, Transferable {
    /// The relative path of the file within the repository.
    public let path: String
    
    /// Whether this diff is from staged changes (true) or unstaged/working tree (false).
    public let isStaged: Bool
    
    public init(path: String, isStaged: Bool) {
        self.path = path
        self.isStaged = isStaged
    }
    
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: GitDiffTransfer.self, contentType: .devysGitDiff)
    }
}
