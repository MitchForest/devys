// DiffFileParser.swift
// Split multi-file git diffs into per-file ParsedDiffs.

import Foundation

struct ParsedDiffFile: Identifiable, Sendable {
    let id = UUID()
    let filePath: String
    let diff: ParsedDiff

    init(filePath: String, diff: ParsedDiff) {
        self.filePath = filePath
        self.diff = diff
    }
}

enum DiffFileParser {
    static func parseFiles(_ diffText: String) -> [ParsedDiffFile] {
        let lines = diffText.components(separatedBy: "\n")
        var chunks: [[String]] = []
        var current: [String] = []

        for line in lines {
            if line.hasPrefix("diff --git") {
                if !current.isEmpty {
                    chunks.append(current)
                    current = []
                }
            }
            current.append(line)
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.compactMap { chunk in
            let text = chunk.joined(separator: "\n")
            let parsed = DiffParser.parse(text)
            if !parsed.hasChanges { return nil }
            let path = parsed.newPath ?? parsed.oldPath ?? parseHeaderPath(from: chunk) ?? "Unknown"
            return ParsedDiffFile(filePath: path, diff: parsed)
        }
    }

    private static func parseHeaderPath(from chunk: [String]) -> String? {
        guard let header = chunk.first(where: { $0.hasPrefix("diff --git") }) else { return nil }
        // Format: diff --git a/path b/path
        let parts = header.components(separatedBy: " ")
        guard parts.count >= 4 else { return nil }
        let bPath = parts[3]
        if bPath.hasPrefix("b/") {
            return String(bPath.dropFirst(2))
        }
        return bPath
    }
}
