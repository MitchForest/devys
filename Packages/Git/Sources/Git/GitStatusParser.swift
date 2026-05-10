import Foundation

public enum GitStatusParser {
    public static func parse(_ output: String) -> [GitFileChange] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(500)
            .flatMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> [GitFileChange] {
        guard line.count >= 3 else { return [] }
        let indexStatus = String(line.prefix(1))
        let worktreeStatus = String(line.dropFirst(1).prefix(1))
        let pathPart = String(line.dropFirst(3))
        let pathComponents = pathPart.components(separatedBy: " -> ")
        let previousPath = pathComponents.count > 1 ? pathComponents.first : nil
        let path = pathComponents.last ?? pathPart

        if indexStatus == "?", worktreeStatus == "?" {
            return [GitFileChange(path: path, status: .untracked, isStaged: false)]
        }

        var changes: [GitFileChange] = []
        if let status = status(for: indexStatus), indexStatus != " " {
            changes.append(GitFileChange(
                path: path,
                previousPath: previousPath,
                status: status,
                isStaged: true
            ))
        }
        if let status = status(for: worktreeStatus), worktreeStatus != " " {
            changes.append(GitFileChange(
                path: path,
                previousPath: previousPath,
                status: status,
                isStaged: false
            ))
        }
        return changes
    }

    private static func status(for character: String) -> GitChangeStatus? {
        switch character {
        case "M":
            .modified
        case "A":
            .added
        case "D":
            .deleted
        case "R":
            .renamed
        case "C":
            .copied
        case "?":
            .untracked
        case "!":
            .ignored
        case "U":
            .unmerged
        default:
            nil
        }
    }
}
