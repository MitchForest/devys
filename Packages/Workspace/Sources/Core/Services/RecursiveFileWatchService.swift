// RecursiveFileWatchService.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreServices

/// File system watcher using FSEvents for recursive monitoring.
///
/// This watcher is designed for higher-level use cases (Git/Chat) where
/// whole-tree change detection is enough and per-directory wiring is too heavy.
public final class RecursiveFileWatchService: FileWatchService, @unchecked Sendable {
    public var onFileChange: FileChangeHandler? {
        get { withLock { onFileChangeHandler } }
        set { withLock { onFileChangeHandler = newValue } }
    }

    private let queue = DispatchQueue(label: "com.devys.recursive-filewatcher", qos: .utility)
    private let lock = NSLock()
    private let debounceInterval: TimeInterval

    private var watchPaths: Set<String>
    private var stream: FSEventStreamRef?
    private var isRunning = false

    private var debounceWorkItem: DispatchWorkItem?
    private var pendingPaths: [String: FileChangeType] = [:]
    private var onFileChangeHandler: FileChangeHandler?

    public init(rootURL: URL, debounceInterval: TimeInterval = 0.2) {
        self.debounceInterval = debounceInterval
        self.watchPaths = [rootURL.path]
    }

    deinit {
        stopWatching()
    }

    public func startWatching() {
        lock.lock()
        let shouldStart = !isRunning
        isRunning = true
        lock.unlock()

        if shouldStart {
            restartStream()
        }
    }

    public func stopWatching() {
        lock.lock()
        isRunning = false
        let streamToStop = stream
        stream = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingPaths.removeAll()
        lock.unlock()

        if let streamToStop {
            FSEventStreamStop(streamToStop)
            FSEventStreamInvalidate(streamToStop)
            FSEventStreamRelease(streamToStop)
        }
    }

    public func watchDirectory(_ url: URL) {
        lock.lock()
        let path = url.path
        let inserted = watchPaths.insert(path).inserted
        let shouldRestart = inserted && isRunning
        lock.unlock()

        if shouldRestart {
            restartStream()
        }
    }

    public func unwatchDirectory(_ url: URL) {
        lock.lock()
        let removed = watchPaths.remove(url.path) != nil
        let shouldRestart = removed && isRunning
        lock.unlock()

        if shouldRestart {
            restartStream()
        }
    }

    // MARK: - Private

    private func restartStream() {
        stopStreamOnly()

        lock.lock()
        let paths = Array(watchPaths)
        lock.unlock()

        guard !paths.isEmpty else { return }

        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<RecursiveFileWatchService>
                .fromOpaque(clientInfo)
                .takeUnretainedValue()
            watcher.handleEvents(
                count: numEvents,
                pathsPointer: eventPaths,
                flagsPointer: eventFlags
            )
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
            )
        )

        guard let stream else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        lock.lock()
        self.stream = stream
        lock.unlock()
    }

    private func stopStreamOnly() {
        let streamToStop = withLock {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            pendingPaths.removeAll()
            let streamToStop = stream
            stream = nil
            return streamToStop
        }

        if let streamToStop {
            FSEventStreamSetDispatchQueue(streamToStop, nil)
            FSEventStreamStop(streamToStop)
            FSEventStreamInvalidate(streamToStop)
            FSEventStreamRelease(streamToStop)
        }
    }

    private func handleEvents(
        count: Int,
        pathsPointer: UnsafeMutableRawPointer,
        flagsPointer: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard count > 0 else { return }
        let paths = Self.decodePaths(count: count, pointer: pathsPointer)
        guard !paths.isEmpty else { return }

        lock.lock()
        for index in 0..<count {
            guard index < paths.count else { break }
            let path = paths[index]
            let flags = flagsPointer[index]
            let changeType = Self.changeType(from: flags)
            pendingPaths[path] = changeType
        }
        lock.unlock()
        scheduleFlush()
    }

    static func decodePaths(count: Int, pointer: UnsafeMutableRawPointer) -> [String] {
        let cfArray = unsafeBitCast(pointer, to: CFArray.self)
        let total = min(count, CFArrayGetCount(cfArray))
        guard total > 0 else { return [] }

        var paths: [String] = []
        paths.reserveCapacity(total)
        for index in 0..<total {
            let rawValue = CFArrayGetValueAtIndex(cfArray, index)
            let cfString = unsafeBitCast(rawValue, to: CFString.self)
            paths.append(cfString as String)
        }
        return paths
    }

    private func scheduleFlush() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingChanges()
        }
        withLock {
            debounceWorkItem?.cancel()
            debounceWorkItem = workItem
        }
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func flushPendingChanges() {
        let (changes, handler) = withLock {
            let changes = pendingPaths
            pendingPaths.removeAll()
            return (changes, onFileChangeHandler)
        }

        guard !changes.isEmpty else { return }

        DispatchQueue.main.async {
            guard let handler else { return }
            for (path, changeType) in changes {
                handler(changeType, URL(fileURLWithPath: path))
            }
        }
    }

    private func withLock<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    static func changeType(from flags: FSEventStreamEventFlags) -> FileChangeType {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
            || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0
            || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0
            || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            return .overflow
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            return .deleted
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            return .renamed
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            return .created
        }
        return .modified
    }
}
