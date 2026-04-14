// RipgrepTextSearchService.swift
// Workspace text search powered by ripgrep.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import Workspace
import Editor

@MainActor
@Observable
final class RipgrepTextSearchService {
    private(set) var results: [WorkspaceTextSearchMatch] = []
    private(set) var isSearching = false
    private(set) var lastError: String?

    private let workspaceID: Workspace.ID
    private let rootURL: URL
    private let explorerSettings: ExplorerSettings
    private let resultLimit: Int

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var runningProcess: Process?
    @ObservationIgnored private var activeQuery = ""

    init(
        workspaceID: Workspace.ID,
        rootURL: URL,
        explorerSettings: ExplorerSettings,
        resultLimit: Int = 200
    ) {
        self.workspaceID = workspaceID
        self.rootURL = rootURL.standardizedFileURL
        self.explorerSettings = explorerSettings
        self.resultLimit = resultLimit
    }

    deinit {
        searchTask?.cancel()
        runningProcess?.terminate()
    }

    func updateQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeQuery = trimmedQuery
        searchTask?.cancel()
        terminateRunningProcess()

        guard !trimmedQuery.isEmpty else {
            results = []
            isSearching = false
            lastError = nil
            return
        }

        isSearching = true
        lastError = nil

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let matches = try await self.executeSearch(query: trimmedQuery)
                guard !Task.isCancelled, self.activeQuery == trimmedQuery else { return }
                self.results = matches
                self.isSearching = false
                self.lastError = nil
                self.runningProcess = nil
                self.searchTask = nil
            } catch is CancellationError {
                if self.activeQuery == trimmedQuery {
                    self.isSearching = false
                }
                self.searchTask = nil
            } catch {
                guard self.activeQuery == trimmedQuery else { return }
                self.results = []
                self.isSearching = false
                self.lastError = error.localizedDescription
                self.runningProcess = nil
                self.searchTask = nil
            }
        }
    }

    func cancel() {
        activeQuery = ""
        searchTask?.cancel()
        terminateRunningProcess()
        results = []
        isSearching = false
        lastError = nil
    }

    private func terminateRunningProcess() {
        runningProcess?.terminate()
        runningProcess = nil
    }

    private func executeSearch(query: String) async throws -> [WorkspaceTextSearchMatch] {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = makeArguments(query: query)
        process.currentDirectoryURL = rootURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        runningProcess = process
        try process.run()

        async let stdoutData = Self.readToEndAsync(from: stdoutPipe.fileHandleForReading)
        async let stderrData = Self.readToEndAsync(from: stderrPipe.fileHandleForReading)

        let outputData = try await stdoutData
        let errorData = (try? await stderrData) ?? Data()
        process.waitUntilExit()
        try Task.checkCancellation()

        let stderr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = process.terminationStatus

        if status != 0, status != 1 {
            throw NSError(
                domain: "RipgrepTextSearchService",
                code: Int(status),
                userInfo: [
                    NSLocalizedDescriptionKey: stderr.isEmpty ? "ripgrep search failed." : stderr
                ]
            )
        }

        let matches = try Self.parseMatches(
            from: outputData,
            workspaceID: workspaceID,
            rootURL: rootURL
        )
        return Array(matches.prefix(resultLimit))
    }

    private func makeArguments(query: String) -> [String] {
        var arguments = [
            "rg",
            "--json",
            "--smart-case",
            "--line-number",
            "--column",
            "--no-heading",
            query
        ]

        if explorerSettings.showDotfiles {
            arguments.append("--hidden")
        }

        for pattern in explorerSettings.excludePatterns.sorted() {
            arguments.append(contentsOf: ["-g", "!\(pattern)"])
        }

        arguments.append(".")
        return arguments
    }
}

extension RipgrepTextSearchService {
    nonisolated static func parseMatches(
        from data: Data,
        workspaceID: Workspace.ID,
        rootURL: URL
    ) throws -> [WorkspaceTextSearchMatch] {
        guard let payload = String(data: data, encoding: .utf8) else { return [] }
        var matches: [WorkspaceTextSearchMatch] = []

        for line in payload.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "match",
                  let matchData = object["data"] as? [String: Any],
                  let pathData = matchData["path"] as? [String: Any],
                  let relativePath = pathData["text"] as? String,
                  let lineNumber = matchData["line_number"] as? Int,
                  let linesData = matchData["lines"] as? [String: Any],
                  let lineText = linesData["text"] as? String,
                  let submatches = matchData["submatches"] as? [[String: Any]],
                  let firstSubmatch = submatches.first,
                  let startOffset = firstSubmatch["start"] as? Int,
                  let endOffset = firstSubmatch["end"] as? Int else {
                continue
            }

            let preview = lineText.trimmingCharacters(in: .newlines)
            let columnNumber = characterColumn(forUTF8Offset: startOffset, in: preview)
            let endColumn = characterColumn(forUTF8Offset: endOffset, in: preview)
            let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL

            matches.append(
                WorkspaceTextSearchMatch(
                    workspaceID: workspaceID,
                    fileURL: fileURL,
                    relativePath: relativePath,
                    lineNumber: lineNumber,
                    columnNumber: columnNumber + 1,
                    preview: preview,
                    match: EditorSearchMatch(
                        startLine: max(0, lineNumber - 1),
                        startColumn: columnNumber,
                        endLine: max(0, lineNumber - 1),
                        endColumn: endColumn
                    )
                )
            )
        }

        return matches
    }

    private nonisolated static func characterColumn(
        forUTF8Offset offset: Int,
        in line: String
    ) -> Int {
        guard offset > 0 else { return 0 }
        let utf8Count = line.utf8.count
        guard offset < utf8Count else { return line.count }

        let utf8Index = line.utf8.index(line.utf8.startIndex, offsetBy: offset)
        if let stringIndex = String.Index(utf8Index, within: line) {
            return line.distance(from: line.startIndex, to: stringIndex)
        }
        return line.count
    }

    private nonisolated static func readToEndAsync(from handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try handle.readToEnd() ?? Data())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
