import Foundation

// MARK: - Diff Models

/// A single line in a diff hunk
public struct DiffLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: LineType
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public enum LineType: Sendable {
        case context   // Unchanged line
        case added     // Added line (+)
        case removed   // Removed line (-)
        case header    // Hunk header (@@ ... @@)
    }

    public init(
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

/// A hunk in a diff (section of changes)
public struct DiffHunk: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(
        id: UUID = UUID(),
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [DiffLine]
    ) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }

    /// Number of added lines in this hunk
    public var addedCount: Int {
        lines.filter { $0.type == .added }.count
    }

    /// Number of removed lines in this hunk
    public var removedCount: Int {
        lines.filter { $0.type == .removed }.count
    }

    /// Generate a git-apply compatible patch for this single hunk
    ///
    /// - Parameters:
    ///   - oldPath: The original file path (e.g., "src/file.swift")
    ///   - newPath: The new file path (usually same as oldPath)
    /// - Returns: A valid unified diff patch string
    public func toPatch(oldPath: String, newPath: String) -> String {
        var patchLines: [String] = []

        // File headers (required for git apply)
        patchLines.append("--- a/\(oldPath)")
        patchLines.append("+++ b/\(newPath)")

        // Hunk header
        patchLines.append(header)

        // Hunk content lines (skip the header line type)
        for line in lines where line.type != .header {
            switch line.type {
            case .added:
                patchLines.append("+\(line.content)")
            case .removed:
                patchLines.append("-\(line.content)")
            case .context:
                patchLines.append(" \(line.content)")
            case .header:
                break
            }
        }

        // Patches must end with newline
        return patchLines.joined(separator: "\n") + "\n"
    }
}

/// Parsed diff for a file
public struct ParsedDiff: Equatable, Sendable {
    public let oldPath: String?
    public let newPath: String?
    public let hunks: [DiffHunk]
    public let isBinary: Bool

    public init(
        oldPath: String? = nil,
        newPath: String? = nil,
        hunks: [DiffHunk] = [],
        isBinary: Bool = false
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
        self.isBinary = isBinary
    }

    /// Total added lines across all hunks
    public var totalAdded: Int {
        hunks.reduce(0) { $0 + $1.addedCount }
    }

    /// Total removed lines across all hunks
    public var totalRemoved: Int {
        hunks.reduce(0) { $0 + $1.removedCount }
    }
}

// MARK: - Diff Parser

/// Parses unified diff format (git diff output)
public enum DiffParser {
    /// Hunk header regex: @@ -oldStart,oldCount +newStart,newCount @@
    private static let hunkHeaderPattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#

    /// Parse a unified diff string into structured hunks
    public static func parse(_ diffText: String) -> ParsedDiff {
        let lines = diffText.components(separatedBy: "\n")

        var oldPath: String?
        var newPath: String?
        var hunks: [DiffHunk] = []
        var isBinary = false

        var currentHunkLines: [DiffLine] = []
        var currentHeader: String?
        var oldStart = 0
        var oldCount = 0
        var newStart = 0
        var newCount = 0
        var oldLineNum = 0
        var newLineNum = 0

        for line in lines {
            // Check for binary file
            if line.hasPrefix("Binary files") {
                isBinary = true
                continue
            }

            // Parse file paths
            if line.hasPrefix("--- ") {
                oldPath = String(line.dropFirst(4))
                if oldPath?.hasPrefix("a/") == true {
                    oldPath = String(oldPath!.dropFirst(2))
                }
                continue
            }

            if line.hasPrefix("+++ ") {
                newPath = String(line.dropFirst(4))
                if newPath?.hasPrefix("b/") == true {
                    newPath = String(newPath!.dropFirst(2))
                }
                continue
            }

            // Parse hunk header
            if line.hasPrefix("@@") {
                // Save previous hunk if exists
                if let header = currentHeader {
                    hunks.append(DiffHunk(
                        header: header,
                        oldStart: oldStart,
                        oldCount: oldCount,
                        newStart: newStart,
                        newCount: newCount,
                        lines: currentHunkLines
                    ))
                    currentHunkLines = []
                }

                // Parse new hunk header
                if let match = parseHunkHeader(line) {
                    currentHeader = line
                    oldStart = match.oldStart
                    oldCount = match.oldCount
                    newStart = match.newStart
                    newCount = match.newCount
                    oldLineNum = oldStart
                    newLineNum = newStart

                    // Add header line
                    currentHunkLines.append(DiffLine(
                        type: .header,
                        content: line
                    ))
                }
                continue
            }

            // Parse diff lines (only if we're in a hunk)
            guard currentHeader != nil else { continue }

            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentHunkLines.append(DiffLine(
                    type: .added,
                    content: String(line.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newLineNum
                ))
                newLineNum += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentHunkLines.append(DiffLine(
                    type: .removed,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil
                ))
                oldLineNum += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                let content = line.isEmpty ? "" : String(line.dropFirst())
                currentHunkLines.append(DiffLine(
                    type: .context,
                    content: content,
                    oldLineNumber: oldLineNum,
                    newLineNumber: newLineNum
                ))
                oldLineNum += 1
                newLineNum += 1
            }
        }

        // Save last hunk
        if let header = currentHeader {
            hunks.append(DiffHunk(
                header: header,
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: currentHunkLines
            ))
        }

        return ParsedDiff(
            oldPath: oldPath,
            newPath: newPath,
            hunks: hunks,
            isBinary: isBinary
        )
    }

    /// Parse hunk header to extract line numbers
    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        guard let regex = try? NSRegularExpression(pattern: hunkHeaderPattern),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ) else {
            return nil
        }

        func extractInt(_ range: NSRange) -> Int {
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: line) else {
                return 1 // Default count is 1 if not specified
            }
            return Int(line[swiftRange]) ?? 1
        }

        let oldStart = extractInt(match.range(at: 1))
        let oldCount = extractInt(match.range(at: 2))
        let newStart = extractInt(match.range(at: 3))
        let newCount = extractInt(match.range(at: 4))

        return (oldStart, oldCount, newStart, newCount)
    }
}
