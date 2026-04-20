// GitRepositoryMetadataWatcher.swift
// Shared watcher for repository metadata changes.

import Foundation
import Darwin

enum GitRepositoryMetadataEvent: Sendable {
    case headChanged
    case indexChanged
    case repositoryStateChanged
}

protocol GitRepositoryMetadataWatcher: AnyObject, Sendable {
    var onChange: (@Sendable (GitRepositoryMetadataEvent) -> Void)? { get set }
    func startWatching()
    func stopWatching()
}

struct GitRepositoryMetadataSnapshot: Equatable, Sendable {
    struct FileState: Equatable, Sendable {
        let exists: Bool
        let size: UInt64?
        let modificationDate: Date?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.exists == rhs.exists &&
                lhs.size == rhs.size &&
                lhs.modificationDate == rhs.modificationDate
        }
    }

    let headContents: String?
    let currentReferenceContents: String?
    let indexState: FileState
    let packedRefsState: FileState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.headContents == rhs.headContents &&
            lhs.currentReferenceContents == rhs.currentReferenceContents &&
            lhs.indexState == rhs.indexState &&
            lhs.packedRefsState == rhs.packedRefsState
    }
}

enum GitRepositoryReferenceResolver {
    static func resolveGitDirectory(for repositoryURL: URL) -> URL? {
        let normalizedRepositoryURL = repositoryURL.standardizedFileURL
        let gitURL = normalizedRepositoryURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return gitURL.standardizedFileURL
        }

        guard let content = try? String(contentsOf: gitURL, encoding: .utf8) else {
            return nil
        }

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("gitdir:") else { continue }
            let pathValue = line.dropFirst("gitdir:".count)
            let path = String(pathValue).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path, relativeTo: normalizedRepositoryURL)
            return url.standardizedFileURL
        }

        return nil
    }

    static func resolveGitCommonDirectory(for repositoryURL: URL) -> URL? {
        guard let gitDirectoryURL = resolveGitDirectory(for: repositoryURL) else {
            return nil
        }

        let commonDirURL = gitDirectoryURL.appendingPathComponent("commondir")
        guard let rawContents = fileContents(at: commonDirURL) else {
            return gitDirectoryURL
        }

        for rawLine in rawContents.split(whereSeparator: \.isNewline) {
            let path = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            return URL(fileURLWithPath: path, relativeTo: gitDirectoryURL).standardizedFileURL
        }

        return gitDirectoryURL
    }

    static func metadataSnapshot(for repositoryURL: URL) -> GitRepositoryMetadataSnapshot? {
        guard let gitDirectoryURL = resolveGitDirectory(for: repositoryURL),
              let commonDirectoryURL = resolveGitCommonDirectory(for: repositoryURL) else {
            return nil
        }

        let headURL = gitDirectoryURL.appendingPathComponent("HEAD")
        let packedRefsURL = commonDirectoryURL.appendingPathComponent("packed-refs")
        let currentReferenceURL = resolveCurrentReferenceURL(for: repositoryURL)

        return GitRepositoryMetadataSnapshot(
            headContents: fileContents(at: headURL),
            currentReferenceContents: currentReferenceURL.flatMap(fileContents(at:)),
            indexState: fileState(at: gitDirectoryURL.appendingPathComponent("index")),
            packedRefsState: fileState(at: packedRefsURL)
        )
    }

    static func resolveCurrentReferenceURL(for repositoryURL: URL) -> URL? {
        guard let gitDirectoryURL = resolveGitDirectory(for: repositoryURL),
              let commonDirectoryURL = resolveGitCommonDirectory(for: repositoryURL) else {
            return nil
        }

        let headURL = gitDirectoryURL.appendingPathComponent("HEAD")
        guard let headContents = fileContents(at: headURL) else {
            return nil
        }

        for rawLine in headContents.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("ref:") else { continue }
            let path = String(line.dropFirst("ref:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            return URL(fileURLWithPath: path, relativeTo: commonDirectoryURL).standardizedFileURL
        }

        return nil
    }

    private static func fileContents(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private static func fileState(at url: URL) -> GitRepositoryMetadataSnapshot.FileState {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return GitRepositoryMetadataSnapshot.FileState(
                exists: false,
                size: nil,
                modificationDate: nil
            )
        }

        return GitRepositoryMetadataSnapshot.FileState(
            exists: true,
            size: (attributes[.size] as? NSNumber)?.uint64Value,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }
}

final class DefaultGitRepositoryMetadataWatcher: GitRepositoryMetadataWatcher, @unchecked Sendable {
    var onChange: (@Sendable (GitRepositoryMetadataEvent) -> Void)? {
        get { withLock { onChangeHandler } }
        set { withLock { onChangeHandler = newValue } }
    }

    private enum WatchKey: Hashable {
        case head
        case index
        case currentReference
        case packedRefs
    }

    private let repositoryURL: URL
    private let queue = DispatchQueue(label: "com.devys.git.repository-metadata-watcher")
    private let lock = NSLock()

    private var watchSources: [WatchKey: DispatchSourceFileSystemObject] = [:]
    private var onChangeHandler: (@Sendable (GitRepositoryMetadataEvent) -> Void)?
    private var isRunning = false

    init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL.standardizedFileURL
    }

    func startWatching() {
        queue.async { [weak self] in
            self?.startWatchingLocked()
        }
    }

    func stopWatching() {
        queue.async { [weak self] in
            self?.stopWatchingLocked()
        }
    }
}

private extension DefaultGitRepositoryMetadataWatcher {
    func startWatchingLocked() {
        guard !isRunning else { return }
        isRunning = true
        rebuildWatchSources()
    }

    func stopWatchingLocked() {
        guard isRunning else { return }
        isRunning = false
        cancelWatchSources()
    }

    func rebuildWatchSources() {
        cancelWatchSources()
        guard
            let gitDirectoryURL = GitRepositoryReferenceResolver.resolveGitDirectory(for: repositoryURL),
            let commonDirectoryURL = GitRepositoryReferenceResolver.resolveGitCommonDirectory(for: repositoryURL)
        else {
            return
        }

        if let source = makeFileWatcher(url: gitDirectoryURL.appendingPathComponent("HEAD"), handler: { [weak self] in
            self?.handleHeadChanged()
        }) {
            watchSources[.head] = source
        }

        if let source = makeFileWatcher(url: gitDirectoryURL.appendingPathComponent("index"), handler: { [weak self] in
            self?.handleIndexChanged()
        }) {
            watchSources[.index] = source
        }

        if let currentReferenceURL = GitRepositoryReferenceResolver.resolveCurrentReferenceURL(for: repositoryURL),
           let source = makeFileWatcher(url: currentReferenceURL, handler: { [weak self] in
               self?.handleRepositoryStateChanged()
           }) {
            watchSources[.currentReference] = source
        }

        if let source = makeFileWatcher(
            url: commonDirectoryURL.appendingPathComponent("packed-refs"),
            handler: { [weak self] in
                self?.handleRepositoryStateChanged()
            }
        ) {
            watchSources[.packedRefs] = source
        }
    }

    func cancelWatchSources() {
        for (_, source) in watchSources {
            source.cancel()
        }
        watchSources.removeAll()
    }

    func emit(_ event: GitRepositoryMetadataEvent) {
        let handler = withLock { onChangeHandler }
        handler?(event)
    }

    func handleHeadChanged() {
        rebuildWatchSources()
        emit(.headChanged)
    }

    func handleIndexChanged() {
        rebuildWatchSources()
        emit(.indexChanged)
    }

    func handleRepositoryStateChanged() {
        rebuildWatchSources()
        emit(.repositoryStateChanged)
    }

    func makeFileWatcher(url: URL, handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        return source
    }

    func withLock<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }
}
