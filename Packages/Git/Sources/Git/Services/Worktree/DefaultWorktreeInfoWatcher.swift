// DefaultWorktreeInfoWatcher.swift
// DevysGit - Worktree info file watcher.

import Foundation
import CoreServices
import Workspace
import Darwin

public final class DefaultWorktreeInfoWatcher: WorktreeInfoWatcher, @unchecked Sendable {
    private enum DebounceKey: Hashable {
        case branch(Worktree.ID)
        case files(Worktree.ID)
    }

    private struct WorktreeWatch {
        let worktree: Worktree
        let metadataWatcher: (any GitRepositoryMetadataWatcher)?
        var fileStream: FileEventStream?

        func stop() {
            metadataWatcher?.stopWatching()
            fileStream?.stop()
        }
    }

    private final class FileEventStream {
        private var stream: FSEventStreamRef?
        private let onEvent: () -> Void

        init(path: String, queue: DispatchQueue, onEvent: @escaping () -> Void) {
            self.onEvent = onEvent

            var context = FSEventStreamContext(
                version: 0,
                info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )

            stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    let watcher = Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue()
                    watcher.onEvent()
                },
                &context,
                [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.2,
                flags
            )

            if let stream {
                FSEventStreamSetDispatchQueue(stream, queue)
                FSEventStreamStart(stream)
            }
        }

        func stop() {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        deinit {
            stop()
        }
    }

    private let queue = DispatchQueue(label: "com.devys.git.worktree-info-watcher")
    private var continuation: AsyncStream<WorktreeInfoEvent>.Continuation?
    private var watches: [Worktree.ID: WorktreeWatch] = [:]
    private var debounceItems: [DebounceKey: DispatchWorkItem] = [:]
    private var pullRequestTrackingEnabled = false
    private var selectedWorktreeId: Worktree.ID?
    private var isStopped = false

    public init() {}

    public func handle(_ command: WorktreeInfoCommand) {
        queue.async { [weak self] in
            self?.handleCommand(command)
        }
    }

    public func eventStream() -> AsyncStream<WorktreeInfoEvent> {
        AsyncStream { continuation in
            queue.async { [weak self] in
                guard let self else { return }
                self.continuation = continuation
                continuation.onTermination = { _ in
                    self.queue.async { [weak self] in
                        self?.stopAll()
                    }
                }
            }
        }
    }

    private func handleCommand(_ command: WorktreeInfoCommand) {
        switch command {
        case .setWorktrees(let worktrees):
            updateWorktrees(worktrees)
        case .setSelectedWorktreeId(let worktreeId):
            selectedWorktreeId = worktreeId
            updateSelectedWorktreeWatch()
        case .setPullRequestTrackingEnabled(let enabled):
            let wasEnabled = pullRequestTrackingEnabled
            pullRequestTrackingEnabled = enabled
            if enabled, !wasEnabled, let repositoryRoot = worktreesRepositoryRoot() {
                emit(.repositoryPullRequestRefresh(repositoryRootURL: repositoryRoot, worktreeIds: Array(watches.keys)))
            }
        case .stop:
            stopAll()
        }
    }

    private func updateWorktrees(_ worktrees: [Worktree]) {
        let incoming = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
        let incomingIds = Set(incoming.keys)
        let existingIds = Set(watches.keys)

        for removedId in existingIds.subtracting(incomingIds) {
            removeWatch(for: removedId)
        }

        for (id, worktree) in incoming {
            if let existing = watches[id],
               existing.worktree == worktree,
               existing.metadataWatcher != nil {
                continue
            }
            removeWatch(for: id)
            startWatch(for: worktree)
        }

        if pullRequestTrackingEnabled, let repositoryRoot = worktreesRepositoryRoot() {
            emit(.repositoryPullRequestRefresh(repositoryRootURL: repositoryRoot, worktreeIds: Array(watches.keys)))
        }
    }

    private func startWatch(for worktree: Worktree) {
        guard !isStopped else { return }
        let metadataWatcher: (any GitRepositoryMetadataWatcher)?
        if GitRepositoryReferenceResolver.resolveGitDirectory(for: worktree.workingDirectory) != nil {
            let watcher = DefaultGitRepositoryMetadataWatcher(repositoryURL: worktree.workingDirectory)
            watcher.onChange = { [weak self] event in
                guard let self else { return }
                switch event {
                case .headChanged:
                    self.schedule(.branchChanged(worktreeId: worktree.id), key: .branch(worktree.id))
                case .indexChanged, .repositoryStateChanged:
                    self.schedule(.filesChanged(worktreeId: worktree.id), key: .files(worktree.id))
                }
            }
            watcher.startWatching()
            metadataWatcher = watcher
        } else {
            metadataWatcher = nil
        }

        watches[worktree.id] = WorktreeWatch(
            worktree: worktree,
            metadataWatcher: metadataWatcher,
            fileStream: makeFileStream(for: worktree.id, worktree: worktree)
        )
    }

    private func updateSelectedWorktreeWatch() {
        for (worktreeId, watch) in watches {
            var updatedWatch = watch
            if worktreeId == selectedWorktreeId {
                if updatedWatch.fileStream == nil {
                    updatedWatch.fileStream = makeFileStream(for: worktreeId, worktree: watch.worktree)
                }
            } else if let fileStream = updatedWatch.fileStream {
                fileStream.stop()
                updatedWatch.fileStream = nil
            }
            watches[worktreeId] = updatedWatch
        }
    }

    private func makeFileStream(for worktreeId: Worktree.ID, worktree: Worktree) -> FileEventStream? {
        guard worktreeId == selectedWorktreeId,
              FileManager.default.fileExists(atPath: worktree.workingDirectory.path) else {
            return nil
        }

        return FileEventStream(
            path: worktree.workingDirectory.path,
            queue: queue
        ) { [weak self] in
            self?.schedule(.filesChanged(worktreeId: worktreeId), key: .files(worktreeId))
        }
    }

    private func removeWatch(for id: Worktree.ID) {
        watches[id]?.stop()
        watches.removeValue(forKey: id)
        debounceItems[.branch(id)]?.cancel()
        debounceItems[.files(id)]?.cancel()
        debounceItems.removeValue(forKey: .branch(id))
        debounceItems.removeValue(forKey: .files(id))
    }

    private func schedule(_ event: WorktreeInfoEvent, key: DebounceKey) {
        debounceItems[key]?.cancel()
        let delay: TimeInterval
        switch key {
        case .branch:
            delay = 0.25
        case .files:
            delay = 1.0
        }
        let item = DispatchWorkItem { [weak self] in
            self?.emit(event)
        }
        debounceItems[key] = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func emit(_ event: WorktreeInfoEvent) {
        guard !isStopped else { return }
        continuation?.yield(event)
    }

    private func worktreesRepositoryRoot() -> URL? {
        watches.values.first?.worktree.repositoryRootURL
    }

    private func stopAll() {
        guard !isStopped else { return }
        isStopped = true
        debounceItems.values.forEach { $0.cancel() }
        debounceItems.removeAll()
        watches.values.forEach { $0.stop() }
        watches.removeAll()
        continuation?.finish()
        continuation = nil
    }
}
