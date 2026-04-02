// DiffModels.swift
// Models for parsing and displaying git diffs.

import Foundation

/// A single line in a diff hunk.
struct DiffLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    
    enum LineType: Sendable, Equatable {
        case context   // Unchanged line
        case added     // Added line (+)
        case removed   // Removed line (-)
        case header    // Hunk header (@@ ... @@)
        case noNewline // "\ No newline at end of file"
    }
    
    init(
        id: UUID = UUID(),
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
struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: UUID
    let header: String
    let lines: [DiffLine]
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    
    init(
        id: UUID = UUID(),
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
    var addedCount: Int {
        lines.filter { $0.type == .added }.count
    }
    
    /// Number of removed lines in this hunk.
    var removedCount: Int {
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
struct ParsedDiff: Equatable, Sendable {
    let hunks: [DiffHunk]
    let isBinary: Bool
    let oldPath: String?
    let newPath: String?
    
    init(
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
    
    var totalAdded: Int {
        hunks.reduce(0) { $0 + $1.addedCount }
    }
    
    var totalRemoved: Int {
        hunks.reduce(0) { $0 + $1.removedCount }
    }
    
    /// Whether the diff has any changes.
    var hasChanges: Bool {
        !hunks.isEmpty || isBinary
    }
}

/// Diff display mode.
enum DiffViewMode: String, Sendable, CaseIterable {
    case unified
    case split
    
    var label: String {
        switch self {
        case .unified: return "Unified"
        case .split: return "Split"
        }
    }
    
    var iconName: String {
        switch self {
        case .unified: return "rectangle.split.1x2"
        case .split: return "rectangle.split.2x1"
        }
    }
}
