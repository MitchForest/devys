import Foundation
import TerminalCore
import TerminalVT

enum TerminalTextRangeMatcher {
    static func latestRange(
        matching query: TerminalTextQuery,
        in lines: [GhosttyTerminalScreenLine],
        snapshotRevision: UInt64
    ) -> TerminalTextRangeLookupResult {
        let queryLines = normalizedQueryLines(query.text)
        guard !queryLines.isEmpty else {
            return .unavailable(.emptyQuery)
        }

        let limitedLines = Array(lines.suffix(query.searchLimitRows))
        if queryLines.count > 1,
           let range = latestExactMultilineRange(
               matching: queryLines,
               in: limitedLines,
               snapshotRevision: snapshotRevision
           ) {
            return .found(range)
        }

        guard let fallbackLine = queryLines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return .unavailable(.emptyQuery)
        }
        guard let range = latestSingleLineRange(
            matching: fallbackLine,
            in: limitedLines,
            snapshotRevision: snapshotRevision
        ) else {
            return .notFound
        }
        return .found(range)
    }

    private static func normalizedQueryLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func latestExactMultilineRange(
        matching queryLines: [String],
        in lines: [GhosttyTerminalScreenLine],
        snapshotRevision: UInt64
    ) -> TerminalTextRange? {
        guard lines.count >= queryLines.count else {
            return nil
        }

        let maxStartIndex = lines.count - queryLines.count
        for startIndex in stride(from: maxStartIndex, through: 0, by: -1) {
            let matches = queryLines.indices.allSatisfy { queryIndex in
                let line = lines[startIndex + queryIndex].text.trimmedRight()
                return line == queryLines[queryIndex]
            }
            guard matches else {
                continue
            }

            let lastQueryLine = queryLines[queryLines.count - 1]
            return TerminalTextRange(
                start: TerminalTextPosition(row: lines[startIndex].row, column: 0),
                end: TerminalTextPosition(
                    row: lines[startIndex + queryLines.count - 1].row,
                    column: max(0, lastQueryLine.count - 1)
                ),
                snapshotRevision: snapshotRevision
            )
        }
        return nil
    }

    private static func latestSingleLineRange(
        matching queryLine: String,
        in lines: [GhosttyTerminalScreenLine],
        snapshotRevision: UInt64
    ) -> TerminalTextRange? {
        for line in lines.reversed() {
            guard let range = line.text.range(of: queryLine) else {
                continue
            }
            let startColumn = line.text.distance(from: line.text.startIndex, to: range.lowerBound)
            let endColumn = max(
                startColumn,
                line.text.distance(from: line.text.startIndex, to: range.upperBound) - 1
            )
            return TerminalTextRange(
                start: TerminalTextPosition(row: line.row, column: startColumn),
                end: TerminalTextPosition(row: line.row, column: endColumn),
                snapshotRevision: snapshotRevision
            )
        }
        return nil
    }
}

private extension String {
    func trimmedRight() -> String {
        var result = self
        while let last = result.unicodeScalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last) {
            result.removeLast()
        }
        return result
    }
}
