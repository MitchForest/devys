// DiffParser.swift
// Parses unified diff format (git diff output).

import Foundation

// swiftlint:disable type_body_length
enum DiffParser {

    /// Parse a unified diff string into a structured ParsedDiff.
    static func parse(_ diffText: String) -> ParsedDiff {
        var parser = Parser(lines: diffText.components(separatedBy: "\n"))
        return parser.parse()
    }

    static func normalizedPatchPath(
        _ rawPath: String,
        droppingPrefix prefix: String? = nil
    ) -> String? {
        let pathWithoutMetadata = rawPath
            .split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? rawPath
        let trimmed = pathWithoutMetadata.trimmingCharacters(in: .whitespaces)
        guard trimmed != "/dev/null" else { return nil }

        let decoded = decodeGitQuotedPathIfNeeded(trimmed)
        if let prefix, decoded.hasPrefix(prefix) {
            return String(decoded.dropFirst(prefix.count))
        }
        return decoded
    }

    static func diffGitHeaderPaths(_ line: String) -> (oldPath: String?, newPath: String?)? {
        guard line.hasPrefix("diff --git ") else { return nil }
        let remainder = String(line.dropFirst("diff --git ".count))
        guard let (oldSpec, newSpec) = splitDiffGitHeaderPathSpecs(remainder) else {
            return nil
        }

        return (
            oldPath: normalizedPatchPath(oldSpec, droppingPrefix: "a/"),
            newPath: normalizedPatchPath(newSpec, droppingPrefix: "b/")
        )
    }

    private static func splitDiffGitHeaderPathSpecs(_ remainder: String) -> (String, String)? {
        for separator in [" \"b/", " b/"] {
            guard let range = remainder.range(of: separator, options: .backwards) else {
                continue
            }

            let oldSpec = String(remainder[..<range.lowerBound])
            let newSpecStart = remainder.index(after: range.lowerBound)
            let newSpec = String(remainder[newSpecStart...])
            guard !oldSpec.isEmpty, !newSpec.isEmpty else { continue }
            return (oldSpec, newSpec)
        }

        let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func decodeGitQuotedPathIfNeeded(_ path: String) -> String {
        guard path.count >= 2, path.first == "\"", path.last == "\"" else {
            return path
        }

        let body = path.dropFirst().dropLast()
        var decoded = ""
        var index = body.startIndex

        while index < body.endIndex {
            let character = body[index]
            guard character == "\\" else {
                decoded.append(character)
                index = body.index(after: index)
                continue
            }

            let escapeStart = body.index(after: index)
            guard escapeStart < body.endIndex else {
                decoded.append("\\")
                break
            }

            let escaped = body[escapeStart]
            switch escaped {
            case "\\":
                decoded.append("\\")
                index = body.index(after: escapeStart)
            case "\"":
                decoded.append("\"")
                index = body.index(after: escapeStart)
            case "t":
                decoded.append("\t")
                index = body.index(after: escapeStart)
            case "n":
                decoded.append("\n")
                index = body.index(after: escapeStart)
            case "r":
                decoded.append("\r")
                index = body.index(after: escapeStart)
            case "0"..."7":
                let decodedOctal = decodeOctalEscape(
                    startingWith: escaped,
                    in: body,
                    escapeStart: escapeStart
                )
                decoded.append(contentsOf: decodedOctal.decodedFragment)
                index = decodedOctal.nextIndex
            default:
                decoded.append(escaped)
                index = body.index(after: escapeStart)
            }
        }

        return decoded
    }

    private static func decodeOctalEscape(
        startingWith firstDigit: Character,
        in body: Substring,
        escapeStart: Substring.Index
    ) -> (decodedFragment: String, nextIndex: Substring.Index) {
        var octal = String(firstDigit)
        var octalIndex = body.index(after: escapeStart)
        while octalIndex < body.endIndex, octal.count < 3 {
            let next = body[octalIndex]
            guard ("0"..."7").contains(next) else { break }
            octal.append(next)
            octalIndex = body.index(after: octalIndex)
        }

        if let value = UInt8(octal, radix: 8),
           let decoded = String(bytes: [value], encoding: .utf8) {
            return (decoded, octalIndex)
        }
        return ("\\\(octal)", octalIndex)
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
        private var currentHunkID: DiffIdentity?
        private var currentHunkIndex = 0
        private var currentLineIndex = 0
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
                if handleMetadataLine(line) {
                    continue
                }
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

        private mutating func handleMetadataLine(_ line: String) -> Bool {
            if let headerPaths = DiffParser.diffGitHeaderPaths(line) {
                oldPath = headerPaths.oldPath
                newPath = headerPaths.newPath
                return true
            }

            if line.hasPrefix("rename from ") {
                oldPath = DiffParser.normalizedPatchPath(
                    String(line.dropFirst("rename from ".count))
                )
                return true
            }

            if line.hasPrefix("rename to ") {
                newPath = DiffParser.normalizedPatchPath(
                    String(line.dropFirst("rename to ".count))
                )
                return true
            }

            if line.hasPrefix("copy from ") {
                oldPath = DiffParser.normalizedPatchPath(
                    String(line.dropFirst("copy from ".count))
                )
                return true
            }

            if line.hasPrefix("copy to ") {
                newPath = DiffParser.normalizedPatchPath(
                    String(line.dropFirst("copy to ".count))
                )
                return true
            }

            return false
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
                oldPath = DiffParser.normalizedPatchPath(
                    String(line.dropFirst(4)),
                    droppingPrefix: "a/"
                )
                return true
            }

            if line.hasPrefix("+++ ") {
                newPath = DiffParser.normalizedPatchPath(
                    String(line.dropFirst(4)),
                    droppingPrefix: "b/"
                )
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
                currentHunkID = makeHunkID(
                    hunkIndex: currentHunkIndex,
                    oldStart: parsed.oldStart,
                    oldCount: parsed.oldCount,
                    newStart: parsed.newStart,
                    newCount: parsed.newCount
                )
                currentLineIndex = 0
                oldLineNum = parsed.oldStart
                newLineNum = parsed.newStart
                currentHunkLines.append(
                    DiffLine(
                        id: makeLineID(
                            hunkID: currentHunkID ?? "hunk-\(currentHunkIndex)",
                            lineIndex: currentLineIndex,
                            type: .header,
                            oldLineNumber: nil,
                            newLineNumber: nil
                        ),
                        type: .header,
                        content: line
                    )
                )
                currentLineIndex += 1
            }
            return true
        }

        private mutating func handleContentLine(_ line: String) {
            if handleNoNewlineMarker(line) { return }
            if handleAddedLine(line) { return }
            if handleRemovedLine(line) { return }
            _ = handleContextLine(line)
        }

        private mutating func handleNoNewlineMarker(_ line: String) -> Bool {
            guard line.hasPrefix("\\ No newline at end of file") else { return false }
            currentHunkLines.append(
                DiffLine(
                    id: nextLineID(type: .noNewline, oldLineNumber: nil, newLineNumber: nil),
                    type: .noNewline,
                    content: "No newline at end of file"
                )
            )
            return true
        }

        private mutating func handleAddedLine(_ line: String) -> Bool {
            guard line.hasPrefix("+"), !line.hasPrefix("+++") else { return false }
            currentHunkLines.append(
                DiffLine(
                    id: nextLineID(type: .added, oldLineNumber: nil, newLineNumber: newLineNum),
                    type: .added,
                    content: String(line.dropFirst()),
                    oldLineNumber: nil,
                    newLineNumber: newLineNum
                )
            )
            newLineNum += 1
            return true
        }

        private mutating func handleRemovedLine(_ line: String) -> Bool {
            guard line.hasPrefix("-"), !line.hasPrefix("---") else { return false }
            currentHunkLines.append(
                DiffLine(
                    id: nextLineID(type: .removed, oldLineNumber: oldLineNum, newLineNumber: nil),
                    type: .removed,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil
                )
            )
            oldLineNum += 1
            return true
        }

        private mutating func handleContextLine(_ line: String) -> Bool {
            guard line.hasPrefix(" ") || line.isEmpty else { return false }
            let content = line.isEmpty ? "" : String(line.dropFirst())
            currentHunkLines.append(
                DiffLine(
                    id: nextLineID(type: .context, oldLineNumber: oldLineNum, newLineNumber: newLineNum),
                    type: .context,
                    content: content,
                    oldLineNumber: oldLineNum,
                    newLineNumber: newLineNum
                )
            )
            oldLineNum += 1
            newLineNum += 1
            return true
        }

        private mutating func finalizeCurrentHunkIfNeeded() {
            guard let currentHeader, let currentHunkID else { return }
            hunks.append(
                DiffHunk(
                    id: currentHunkID,
                    header: currentHeader,
                    lines: currentHunkLines,
                    oldStart: currentOldStart,
                    oldCount: currentOldCount,
                    newStart: currentNewStart,
                    newCount: currentNewCount
                )
            )
            currentHunkLines = []
            self.currentHeader = nil
            self.currentHunkID = nil
            currentHunkIndex += 1
        }

        private mutating func nextLineID(
            type: DiffLine.LineType,
            oldLineNumber: Int?,
            newLineNumber: Int?
        ) -> DiffIdentity {
            defer { currentLineIndex += 1 }
            return makeLineID(
                hunkID: currentHunkID ?? "hunk-\(currentHunkIndex)",
                lineIndex: currentLineIndex,
                type: type,
                oldLineNumber: oldLineNumber,
                newLineNumber: newLineNumber
            )
        }

        private func makeHunkID(
            hunkIndex: Int,
            oldStart: Int,
            oldCount: Int,
            newStart: Int,
            newCount: Int
        ) -> DiffIdentity {
            "hunk:\(hunkIndex):\(oldStart):\(oldCount):\(newStart):\(newCount)"
        }

        private func makeLineID(
            hunkID: DiffIdentity,
            lineIndex: Int,
            type: DiffLine.LineType,
            oldLineNumber: Int?,
            newLineNumber: Int?
        ) -> DiffIdentity {
            let oldComponent = oldLineNumber.map(String.init) ?? "nil"
            let newComponent = newLineNumber.map(String.init) ?? "nil"
            return "\(hunkID):line:\(lineIndex):\(type.debugName):\(oldComponent):\(newComponent)"
        }
    }
}
// swiftlint:enable type_body_length

extension DiffLine.LineType {
    var debugName: String {
        switch self {
        case .context: return "context"
        case .added: return "added"
        case .removed: return "removed"
        case .header: return "header"
        case .noNewline: return "no-newline"
        }
    }
}
