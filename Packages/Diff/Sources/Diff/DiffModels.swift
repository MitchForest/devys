// DiffModels.swift
// Models for parsing and displaying git diffs.

import Foundation

public typealias DiffIdentity = String

/// A single line in a diff hunk.
public struct DiffLine: Identifiable, Equatable, Sendable {
    public let id: DiffIdentity
    public let type: LineType
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public enum LineType: Sendable, Equatable {
        case context   // Unchanged line
        case added     // Added line (+)
        case removed   // Removed line (-)
        case header    // Hunk header (@@ ... @@)
        case noNewline // "\ No newline at end of file"
    }

    public init(
        id: DiffIdentity,
        type: LineType,
        content: String,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

/// A hunk in a diff (section of changes).
public struct DiffHunk: Identifiable, Equatable, Sendable {
    public let id: DiffIdentity
    public let header: String
    public let lines: [DiffLine]
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int

    public init(
        id: DiffIdentity,
        header: String,
        lines: [DiffLine],
        oldStart: Int = 1,
        oldCount: Int = 0,
        newStart: Int = 1,
        newCount: Int = 0
    ) {
        self.id = id
        self.header = header
        self.lines = lines
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
    }

    /// Number of added lines in this hunk.
    public var addedCount: Int {
        lines.filter { $0.type == .added }.count
    }

    /// Number of removed lines in this hunk.
    public var removedCount: Int {
        lines.filter { $0.type == .removed }.count
    }

    /// Generate a git-apply compatible patch for this single hunk.
    func toPatch(oldPath: String, newPath: String) -> String {
        var patchLines: [String] = []

        patchLines.append("--- a/\(oldPath)")
        patchLines.append("+++ b/\(newPath)")
        patchLines.append(header)

        for line in lines where line.type != .header {
            switch line.type {
            case .added:
                patchLines.append("+\(line.content)")
            case .removed:
                patchLines.append("-\(line.content)")
            case .context:
                patchLines.append(" \(line.content)")
            case .noNewline:
                patchLines.append("\\ No newline at end of file")
            case .header:
                break
            }
        }

        return patchLines.joined(separator: "\n") + "\n"
    }

}

/// Parsed diff for a file.
public struct ParsedDiff: Equatable, Sendable {
    public let hunks: [DiffHunk]
    public let isBinary: Bool
    public let oldPath: String?
    public let newPath: String?

    public init(
        hunks: [DiffHunk] = [],
        isBinary: Bool = false,
        oldPath: String? = nil,
        newPath: String? = nil
    ) {
        self.hunks = hunks
        self.isBinary = isBinary
        self.oldPath = oldPath
        self.newPath = newPath
    }

    // periphery:ignore - surfaced in diff summaries and diagnostics views
    public var totalAdded: Int {
        hunks.reduce(0) { $0 + $1.addedCount }
    }

    // periphery:ignore - surfaced in diff summaries and diagnostics views
    public var totalRemoved: Int {
        hunks.reduce(0) { $0 + $1.removedCount }
    }

    /// Whether the diff has any changes.
    public var hasChanges: Bool {
        !hunks.isEmpty || isBinary || oldPath != newPath
    }
}

/// Diff display mode.
public enum DiffViewMode: String, Sendable, CaseIterable {
    case unified
    case split

    public var label: String {
        switch self {
        case .unified: return "Unified"
        case .split: return "Split"
        }
    }

    public var iconName: String {
        switch self {
        case .unified: return "rectangle.split.1x2"
        case .split: return "rectangle.split.2x1"
        }
    }
}
