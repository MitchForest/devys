import Diff
import Foundation

enum GitPatchBuilder {
    static func patch(for hunk: DiffHunk, change: GitFileChange) -> String {
        let oldPath = oldPath(for: change)
        let newPath = newPath(for: change)
        let oldHeader = oldPath.map { "a/\($0)" } ?? "/dev/null"
        let newHeader = newPath.map { "b/\($0)" } ?? "/dev/null"
        let diffOld = oldPath.map { "a/\($0)" } ?? newHeader
        let diffNew = newPath.map { "b/\($0)" } ?? oldHeader

        var patchLines: [String] = [
            "diff --git \(diffOld) \(diffNew)",
            "--- \(oldHeader)",
            "+++ \(newHeader)",
            hunk.header
        ]

        for line in hunk.lines where line.type != .header {
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

    private static func oldPath(for change: GitFileChange) -> String? {
        switch change.status {
        case .added, .untracked:
            nil
        case .modified, .deleted, .renamed, .copied, .ignored, .unmerged:
            change.previousPath ?? change.path
        }
    }

    private static func newPath(for change: GitFileChange) -> String? {
        switch change.status {
        case .deleted:
            nil
        case .modified, .added, .renamed, .copied, .untracked, .ignored, .unmerged:
            change.path
        }
    }
}
