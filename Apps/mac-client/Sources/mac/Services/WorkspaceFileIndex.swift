// WorkspaceFileIndex.swift
// Cached per-workspace file listing for quick open.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import Workspace

@MainActor
@Observable
final class WorkspaceFileIndex {
    struct Entry: Identifiable, Equatable, Sendable {
        let fileURL: URL
        let relativePath: String
        let fileName: String
        let searchablePath: String
        let searchableFileName: String

        var id: String {
            fileURL.path
        }
    }

    struct Match: Identifiable, Equatable, Sendable {
        let entry: Entry
        let score: Int

        var id: String {
            entry.id
        }
    }

    private(set) var entries: [Entry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let rootURL: URL
    private let settingsProvider: @MainActor () -> ExplorerSettings
    private let watcher: RecursiveFileWatchService
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var reloadDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private var hasLoaded = false

    init(
        rootURL: URL,
        settingsProvider: @escaping @MainActor () -> ExplorerSettings
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.settingsProvider = settingsProvider
        self.watcher = RecursiveFileWatchService(rootURL: rootURL)
        self.watcher.onFileChange = { [weak self] changeType, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleFileChange(changeType)
            }
        }
    }

    deinit {
        reloadDebounceTask?.cancel()
        loadTask?.cancel()
    }

    func activate() {
        if !isWatching {
            watcher.startWatching()
            isWatching = true
        }

        if !hasLoaded && loadTask == nil {
            reload()
        }
    }

    func deactivate() {
        guard isWatching else { return }
        watcher.stopWatching()
        isWatching = false
    }

    func reload() {
        let explorerSettings = settingsProvider()
        loadTask?.cancel()
        isLoading = true
        lastError = nil

        let rootURL = self.rootURL
        loadTask = Task {
            do {
                let loadedEntries = try await Task.detached(priority: .userInitiated) {
                    try Self.buildEntries(
                        rootURL: rootURL,
                        explorerSettings: explorerSettings
                    )
                }.value

                guard !Task.isCancelled else { return }
                entries = loadedEntries
                isLoading = false
                hasLoaded = true
                lastError = nil
                loadTask = nil
            } catch is CancellationError {
                isLoading = false
                loadTask = nil
            } catch {
                isLoading = false
                hasLoaded = true
                lastError = error.localizedDescription
                loadTask = nil
            }
        }
    }

    func matches(
        for query: String,
        limit: Int = 200,
        openURLs: Set<URL> = []
    ) -> [Match] {
        guard limit > 0 else { return [] }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOpenURLs = Set(openURLs.map(\.standardizedFileURL))

        guard !trimmedQuery.isEmpty else {
            return entries
                .sorted {
                    Self.sort(lhs: $0, rhs: $1, lhsScore: 0, rhsScore: 0, openURLs: normalizedOpenURLs)
                }
                .prefix(limit)
                .map { Match(entry: $0, score: 0) }
        }

        let normalizedQuery = trimmedQuery.lowercased()
        return Array(
            entries
                .compactMap { entry in
                    guard let score = Self.score(for: normalizedQuery, entry: entry) else {
                        return nil
                    }
                    return Match(entry: entry, score: score)
                }
                .sorted {
                    Self.sort(
                        lhs: $0.entry,
                        rhs: $1.entry,
                        lhsScore: $0.score,
                        rhsScore: $1.score,
                        openURLs: normalizedOpenURLs
                    )
                }
                .prefix(limit)
        )
    }

    private func handleFileChange(_ changeType: FileChangeType) {
        switch changeType {
        case .modified:
            return
        case .created, .deleted, .renamed, .overflow:
            scheduleReload()
        }
    }

    private func scheduleReload() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

private extension WorkspaceFileIndex {
    nonisolated static func buildEntries(
        rootURL: URL,
        explorerSettings: ExplorerSettings
    ) throws -> [Entry] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [],
            errorHandler: nil
        ) else {
            return []
        }

        var entries: [Entry] = []
        entries.reserveCapacity(2_048)

        while let next = enumerator.nextObject() as? URL {
            let resourceValues = try next.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let name = next.lastPathComponent

            if explorerSettings.shouldExclude(name) {
                if resourceValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard resourceValues.isRegularFile == true else { continue }
            let relativePath = relativePath(for: next, rootURL: rootURL)
            entries.append(
                Entry(
                    fileURL: next.standardizedFileURL,
                    relativePath: relativePath,
                    fileName: next.lastPathComponent,
                    searchablePath: relativePath.lowercased(),
                    searchableFileName: next.lastPathComponent.lowercased()
                )
            )
        }

        return entries.sorted { lhs, rhs in
            lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }

    nonisolated static func relativePath(
        for fileURL: URL,
        rootURL: URL
    ) -> String {
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL

        let rootComponents = resolvedRootURL.pathComponents
        let fileComponents = resolvedFileURL.pathComponents

        guard fileComponents.starts(with: rootComponents) else {
            return fileURL.lastPathComponent
        }

        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        guard !relativeComponents.isEmpty else {
            return fileURL.lastPathComponent
        }

        return NSString.path(withComponents: relativeComponents)
    }

    nonisolated static func score(
        for normalizedQuery: String,
        entry: Entry
    ) -> Int? {
        if entry.searchableFileName == normalizedQuery {
            return 0
        }
        if entry.searchableFileName.hasPrefix(normalizedQuery) {
            return 20 + entry.fileName.count
        }
        if let range = entry.searchableFileName.range(of: normalizedQuery) {
            let offset = entry.searchableFileName.distance(
                from: entry.searchableFileName.startIndex,
                to: range.lowerBound
            )
            return 80 + offset
        }
        if entry.searchablePath.hasPrefix(normalizedQuery) {
            return 140 + entry.relativePath.count
        }
        if let range = entry.searchablePath.range(of: normalizedQuery) {
            let offset = entry.searchablePath.distance(
                from: entry.searchablePath.startIndex,
                to: range.lowerBound
            )
            return 220 + offset
        }
        if let subsequencePenalty = subsequencePenalty(
            query: normalizedQuery,
            haystack: entry.searchablePath
        ) {
            return 400 + subsequencePenalty
        }
        return nil
    }

    nonisolated static func subsequencePenalty(
        query: String,
        haystack: String
    ) -> Int? {
        guard !query.isEmpty else { return 0 }

        var queryIndex = query.startIndex
        var penalty = 0
        var previousMatchOffset: Int?

        for (offset, character) in haystack.enumerated() {
            guard queryIndex < query.endIndex else { break }
            if character == query[queryIndex] {
                if let previousMatchOffset {
                    penalty += max(0, offset - previousMatchOffset - 1)
                }
                previousMatchOffset = offset
                query.formIndex(after: &queryIndex)
            }
        }

        return queryIndex == query.endIndex ? penalty : nil
    }

    nonisolated static func sort(
        lhs: Entry,
        rhs: Entry,
        lhsScore: Int,
        rhsScore: Int,
        openURLs: Set<URL>
    ) -> Bool {
        let lhsOpen = openURLs.contains(lhs.fileURL)
        let rhsOpen = openURLs.contains(rhs.fileURL)
        if lhsOpen != rhsOpen {
            return lhsOpen
        }
        if lhsScore != rhsScore {
            return lhsScore < rhsScore
        }
        if lhs.relativePath.count != rhs.relativePath.count {
            return lhs.relativePath.count < rhs.relativePath.count
        }
        return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
    }
}
