import ComposableArchitecture
import Foundation

struct ProjectFilesRequest: Equatable, Sendable {
    var rootURL: URL
    var expandedDirectoryPaths: Set<String>
    var query: String
    var rowBudget: Int

    init(
        rootURL: URL,
        expandedDirectoryPaths: Set<String> = [],
        query: String = "",
        rowBudget: Int = 320
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.expandedDirectoryPaths = expandedDirectoryPaths
        self.query = query
        self.rowBudget = rowBudget
    }
}

struct ProjectFileRow: Equatable, Identifiable, Sendable {
    var url: URL
    var isDirectory: Bool
    var depth: Int

    var id: String { url.standardizedFileURL.path }
}

struct ProjectFilesClient: Sendable {
    var loadRows: @Sendable (ProjectFilesRequest) async -> [ProjectFileRow]

    init(loadRows: @escaping @Sendable (ProjectFilesRequest) async -> [ProjectFileRow]) {
        self.loadRows = loadRows
    }
}

private enum ProjectFilesClientKey: DependencyKey {
    static let liveValue = ProjectFilesClient.liveValue
}

extension DependencyValues {
    var projectFilesClient: ProjectFilesClient {
        get { self[ProjectFilesClientKey.self] }
        set { self[ProjectFilesClientKey.self] = newValue }
    }
}

extension ProjectFilesClient {
    static let liveValue = ProjectFilesClient { request in
        await Task.detached(priority: .userInitiated) {
            loadRowsSynchronously(request)
        }.value
    }

    nonisolated static func loadRowsSynchronously(_ request: ProjectFilesRequest) -> [ProjectFileRow] {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return visibleRows(
                rootURL: request.rootURL,
                expandedDirectoryPaths: request.expandedDirectoryPaths,
                rowBudget: request.rowBudget
            )
        }

        return searchedRows(
            rootURL: request.rootURL,
            query: trimmedQuery,
            rowBudget: request.rowBudget
        )
    }

    nonisolated private static func visibleRows(
        rootURL: URL,
        expandedDirectoryPaths: Set<String>,
        rowBudget: Int
    ) -> [ProjectFileRow] {
        var rows: [ProjectFileRow] = []
        appendRows(
            rootURL,
            depth: 0,
            expandedDirectoryPaths: expandedDirectoryPaths,
            rows: &rows,
            rowBudget: rowBudget
        )
        return rows
    }

    nonisolated private static func searchedRows(
        rootURL: URL,
        query: String,
        rowBudget: Int
    ) -> [ProjectFileRow] {
        guard rowBudget > 0,
              let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var rows: [ProjectFileRow] = []
        let lowercasedQuery = query.lowercased()

        for case let url as URL in enumerator {
            guard !Task.isCancelled else { break }

            if noisyDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            let relativePath = url.path.replacingOccurrences(
                of: rootURL.path + "/",
                with: ""
            )
            guard relativePath.lowercased().contains(lowercasedQuery) else { continue }

            let isDirectory = isDirectory(url)
            let depth = max(relativePath.split(separator: "/").count - 1, 0)
            rows.append(
                ProjectFileRow(
                    url: url.standardizedFileURL,
                    isDirectory: isDirectory,
                    depth: depth
                )
            )

            if rows.count >= rowBudget {
                break
            }
        }

        return rows
    }

    nonisolated private static func appendRows(
        _ directoryURL: URL,
        depth: Int,
        expandedDirectoryPaths: Set<String>,
        rows: inout [ProjectFileRow],
        rowBudget: Int
    ) {
        guard rowBudget > 0, rows.count < rowBudget else { return }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sortedContents = contents
            .filter { !noisyDirectoryNames.contains($0.lastPathComponent) }
            .sorted { lhs, rhs in
                let lhsIsDirectory = isDirectory(lhs)
                let rhsIsDirectory = isDirectory(rhs)
                if lhsIsDirectory != rhsIsDirectory {
                    return lhsIsDirectory && !rhsIsDirectory
                }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        for child in sortedContents {
            guard rows.count < rowBudget, !Task.isCancelled else { return }
            let childIsDirectory = isDirectory(child)
            rows.append(
                ProjectFileRow(
                    url: child.standardizedFileURL,
                    isDirectory: childIsDirectory,
                    depth: depth
                )
            )

            if childIsDirectory,
               expandedDirectoryPaths.contains(child.standardizedFileURL.path) {
                appendRows(
                    child,
                    depth: depth + 1,
                    expandedDirectoryPaths: expandedDirectoryPaths,
                    rows: &rows,
                    rowBudget: rowBudget
                )
            }
        }
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    nonisolated private static let noisyDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "build",
        "node_modules",
    ]
}
