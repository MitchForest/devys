// DiffParser.swift
// Parses unified diff format (git diff output).

import Foundation

/// Parses unified diff format (git diff output).
enum DiffParser {
    
    /// Parse a unified diff string into a structured ParsedDiff.
    static func parse(_ diffText: String) -> ParsedDiff {
        var parser = Parser(lines: diffText.components(separatedBy: "\n"))
        return parser.parse()
    }
    
    // MARK: - Private
    
    fileprivate struct HunkHeader {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }
    
    /// Parse hunk header like "@@ -1,3 +1,5 @@" or "@@ -1 +1,2 @@"
    private static func parseHunkHeader(_ line: String) -> HunkHeader? {
        // Pattern: @@ -oldStart[,oldCount] +newStart[,newCount] @@
        let pattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        func extractInt(_ rangeIndex: Int, default defaultValue: Int = 1) -> Int {
            let range = match.range(at: rangeIndex)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: line) else {
                return defaultValue
            }
            return Int(line[swiftRange]) ?? defaultValue
        }
        
        return HunkHeader(
            oldStart: extractInt(1),
            oldCount: extractInt(2),
            newStart: extractInt(3),
            newCount: extractInt(4)
        )
    }

    fileprivate struct Parser {
        let lines: [String]

        private var hunks: [DiffHunk] = []
        private var isBinary = false
        private var oldPath: String?
        private var newPath: String?

        private var currentHunkLines: [DiffLine] = []
        private var currentHeader: String?
        private var oldLineNum = 0
        private var newLineNum = 0
        private var currentOldStart = 0
        private var currentOldCount = 0
        private var currentNewStart = 0
        private var currentNewCount = 0

        init(lines: [String]) {
            self.lines = lines
        }

        mutating func parse() -> ParsedDiff {
            for line in lines {
                if handleBinaryIndicator(line) {
                    continue
                }
                if handlePathLine(line) {
                    continue
                }
                if handleHunkHeader(line) {
                    continue
                }
                guard currentHeader != nil else { continue }
                handleContentLine(line)
            }

            finalizeCurrentHunkIfNeeded()

            return ParsedDiff(
                hunks: hunks,
                isBinary: isBinary,
                oldPath: oldPath,
                newPath: newPath
            )
        }

        private mutating func handleBinaryIndicator(_ line: String) -> Bool {
            if line.hasPrefix("Binary files") {
                isBinary = true
                return true
            }
            return false
        }

        private mutating func handlePathLine(_ line: String) -> Bool {
            if line.hasPrefix("--- ") {
                let path = String(line.dropFirst(4))
                if path.hasPrefix("a/") {
                    oldPath = String(path.dropFirst(2))
                } else if path != "/dev/null" {
                    oldPath = path
                }
                return true
            }

            if line.hasPrefix("+++ ") {
                let path = String(line.dropFirst(4))
                if path.hasPrefix("b/") {
                    newPath = String(path.dropFirst(2))
                } else if path != "/dev/null" {
                    newPath = path
                }
                return true
            }

            return false
        }

        private mutating func handleHunkHeader(_ line: String) -> Bool {
            guard line.hasPrefix("@@") else { return false }
            finalizeCurrentHunkIfNeeded()
            if let parsed = DiffParser.parseHunkHeader(line) {
                currentHeader = line
                currentOldStart = parsed.oldStart
                currentOldCount = parsed.oldCount
                currentNewStart = parsed.newStart
                currentNewCount = parsed.newCount
                oldLineNum = parsed.oldStart
                newLineNum = parsed.newStart
                currentHunkLines.append(DiffLine(type: .header, content: line))
            }
            return true
        }

        private mutating func handleContentLine(_ line: String) {
            if line.hasPrefix("\\ No newline at end of file") {
                currentHunkLines.append(DiffLine(
                    type: .noNewline,
                    content: "No newline at end of file"
                ))
                return
            }

            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentHunkLines.append(DiffLine(
                    type: .added,
                    content: String(line.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newLineNum
                ))
                newLineNum += 1
                return
            }

            if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentHunkLines.append(DiffLine(
                    type: .removed,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil
                ))
                oldLineNum += 1
                return
            }

            if line.hasPrefix(" ") || line.isEmpty {
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

        private mutating func finalizeCurrentHunkIfNeeded() {
            guard let header = currentHeader else { return }
            hunks.append(DiffHunk(
                header: header,
                lines: currentHunkLines,
                oldStart: currentOldStart,
                oldCount: currentOldCount,
                newStart: currentNewStart,
                newCount: currentNewCount
            ))
            currentHunkLines = []
            currentHeader = nil
        }
    }
}
