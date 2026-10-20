import CryptoKit
import Foundation

/// A review comment anchored to lines of one file in a patch, with the hunk it was written
/// against so the reader can tell whether those lines have moved since. The same shape and
/// message line as the diff surface's `DiffComment` (`src/surfaces/diff.tsx`).
public struct DiffComment: Equatable, Sendable, Codable {
    public let path: String
    /// "additions" (the new side) or "deletions" (the old side).
    public let side: String
    public let start: Int
    public let end: Int
    /// The first 8 hex digits of the SHA-256 of the hunk's text (`hunkText`).
    public let hunk: String
    /// The base commit the patch is against, when known.
    public let base: String?
    public let text: String

    public init(path: String, side: String, start: Int, end: Int, hunk: String, base: String? = nil, text: String) {
        self.path = path
        self.side = side
        self.start = start
        self.end = end
        self.hunk = hunk
        self.base = base
        self.text = text
    }

    /// A comment on the selected lines of `patch`, its hunk hashed from the patch.
    public init(_ selection: DiffSelection, in patch: String, base: String?, text: String) {
        self.init(
            path: selection.path,
            side: selection.side,
            start: selection.start,
            end: selection.end,
            hunk: Self.hunkHash(Self.hunkText(patch, selection)),
            base: base,
            text: text
        )
    }

    /// How the comment reads in the message that carries it:
    /// `<path> <lines a–b | line a> (<new|old>, base <commit>, hunk <hash>): <text>`.
    public var line: String {
        let lines = start == end ? "line \(start)" : "lines \(start)–\(end)"
        let base = base.map { "base \($0.prefix(8)), " } ?? ""
        return "\(path) \(lines) (\(side == "deletions" ? "old" : "new"), \(base)hunk \(hunk)): \(text)"
    }

    /// The one message pending comments leave as: a heading, then one line per comment.
    public static func review(_ title: String, _ comments: [Self]) -> String {
        (["Review comments on \(title):"] + comments.map(\.line)).joined(separator: "\n")
    }

    /// The text of the hunk holding a selection's first line: its `@@` header through its last
    /// line, joined by newlines with no trailing newline. Empty when the patch has no such hunk.
    public static func hunkText(_ patch: String, _ selection: DiffSelection) -> String {
        let lines = patch.components(separatedBy: "\n")
        var oldPath = ""
        var newPath = ""
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("diff --git ") {
                (oldPath, newPath) = ("", "")
            } else if line.hasPrefix("--- ") {
                oldPath = strip(line.dropFirst(4).trimmingCharacters(in: .whitespaces), "a/")
            } else if line.hasPrefix("+++ ") {
                newPath = strip(line.dropFirst(4).trimmingCharacters(in: .whitespaces), "b/")
            }
            guard let header = HunkHeader(line) else {
                index += 1
                continue
            }
            // The hunk runs until both sides' line counts are used up.
            var end = index + 1
            var old = header.oldCount
            var added = header.newCount
            while end < lines.count, old > 0 || added > 0 {
                let current = lines[end]
                if current.hasPrefix("-") {
                    old -= 1
                } else if current.hasPrefix("+") {
                    added -= 1
                } else if current.hasPrefix(" ") || current.isEmpty {
                    old -= 1
                    added -= 1
                }
                end += 1
            }
            while end < lines.count, lines[end].hasPrefix("\\") { end += 1 }
            let (start, count) = selection.side == "deletions" ? (header.oldStart, header.oldCount) : (header.newStart, header.newCount)
            let inFile = selection.path == newPath || selection.path == oldPath
            if inFile, selection.start >= start, selection.start < start + max(count, 1) {
                return lines[index..<end].joined(separator: "\n")
            }
            index = end
        }
        return ""
    }

    /// The first 8 hex digits of the SHA-256 of a hunk's UTF-8 text.
    public static func hunkHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private static func strip(_ path: String, _ prefix: String) -> String {
        path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

/// `@@ -a[,b] +c[,d] @@`: where a hunk starts on each side and how many lines it spans.
private struct HunkHeader {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int

    init?(_ line: String) {
        guard let match = line.prefixMatch(of: /@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/),
              let oldStart = Int(match.1), let newStart = Int(match.3)
        else { return nil }
        self.oldStart = oldStart
        oldCount = match.2.flatMap { Int($0) } ?? 1
        self.newStart = newStart
        newCount = match.4.flatMap { Int($0) } ?? 1
    }
}
