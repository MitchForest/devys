// SharedFileWatchRegistry.swift
// DevysCore - Shared root watcher ownership for file tree consumers.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Shares a single root watcher transport across multiple consumers of the same workspace.
public final class SharedFileWatchRegistry: @unchecked Sendable {
    public typealias TransportFactory = (URL) -> FileWatchService

    public static let shared = SharedFileWatchRegistry()

    private let lock = NSLock()
    private let transportFactory: TransportFactory
    private var statesByRootURL: [URL: RootWatcherState] = [:]

    public init(
        transportFactory: @escaping TransportFactory = {
            RecursiveFileWatchService(rootURL: $0)
        }
    ) {
        self.transportFactory = transportFactory
    }

    public func makeService(rootURL: URL) -> FileWatchService {
        SharedFileWatchClient(
            rootURL: rootURL.standardizedFileURL,
            registry: self
        )
    }
}

private extension SharedFileWatchRegistry {
    func activateClient(
        id: UUID,
        rootURL: URL,
        handler: @escaping FileChangeHandler
    ) {
        let state = withLock {
            if let existing = statesByRootURL[rootURL] {
                return existing
            }

            let state = RootWatcherState(
                rootURL: rootURL,
                transport: transportFactory(rootURL)
            )
            statesByRootURL[rootURL] = state
            return state
        }

        state.addListener(id: id, handler: handler)
    }

    func deactivateClient(id: UUID, rootURL: URL) {
        let state = withLock { statesByRootURL[rootURL] }
        state?.removeListener(id: id)
    }

    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class SharedFileWatchClient: FileWatchService, @unchecked Sendable {
    let rootURL: URL

    private let registry: SharedFileWatchRegistry
    private let id = UUID()
    private let lock = NSLock()

    private var isWatching = false
    private var onFileChangeStorage: FileChangeHandler?

    init(rootURL: URL, registry: SharedFileWatchRegistry) {
        self.rootURL = rootURL
        self.registry = registry
    }

    deinit {
        stopWatching()
    }

    var onFileChange: FileChangeHandler? {
        get {
            lock.withLock { onFileChangeStorage }
        }
        set {
            lock.withLock {
                onFileChangeStorage = newValue
            }
        }
    }

    func startWatching() {
        let shouldStart = lock.withLock { () -> Bool in
            guard !isWatching else { return false }
            isWatching = true
            return true
        }
        guard shouldStart else { return }

        registry.activateClient(id: id, rootURL: rootURL) { [weak self] changeType, url in
            self?.dispatch(changeType: changeType, url: url)
        }
    }

    func stopWatching() {
        let shouldStop = lock.withLock { () -> Bool in
            guard isWatching else { return false }
            isWatching = false
            return true
        }
        guard shouldStop else { return }

        registry.deactivateClient(id: id, rootURL: rootURL)
    }

    func watchDirectory(_ url: URL) {
        _ = url
    }

    func unwatchDirectory(_ url: URL) {
        _ = url
    }

    private func dispatch(changeType: FileChangeType, url: URL) {
        let handler = lock.withLock { onFileChangeStorage }
        handler?(changeType, url)
    }
}

private final class RootWatcherState: @unchecked Sendable {
    private let transport: FileWatchService
    private let lock = NSLock()

    private var listenerHandlers: [UUID: FileChangeHandler] = [:]
    private var isTransportRunning = false

    init(rootURL: URL, transport: FileWatchService) {
        _ = rootURL
        self.transport = transport
        transport.onFileChange = { [weak self] changeType, url in
            self?.dispatch(changeType: changeType, url: url)
        }
    }

    func addListener(id: UUID, handler: @escaping FileChangeHandler) {
        let shouldStart = lock.withLock { () -> Bool in
            listenerHandlers[id] = handler
            guard !isTransportRunning else { return false }
            isTransportRunning = true
            return true
        }

        if shouldStart {
            transport.startWatching()
        }
    }

    func removeListener(id: UUID) {
        let shouldStop = lock.withLock { () -> Bool in
            listenerHandlers.removeValue(forKey: id)
            guard listenerHandlers.isEmpty, isTransportRunning else { return false }
            isTransportRunning = false
            return true
        }

        if shouldStop {
            transport.stopWatching()
        }
    }

    private func dispatch(changeType: FileChangeType, url: URL) {
        let handlers = lock.withLock { Array(listenerHandlers.values) }
        for handler in handlers {
            handler(changeType, url)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
