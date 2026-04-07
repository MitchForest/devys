import Foundation
import Testing
@testable import Workspace

@Suite("Shared File Watch Registry Tests")
struct SharedFileWatchRegistryTests {
    @Test("Two consumers of the same root share one watcher transport")
    func sharesWatcherTransportPerRoot() {
        let factory = RecordingWatchTransportFactory()
        let registry = SharedFileWatchRegistry(transportFactory: factory.make(rootURL:))
        let rootURL = URL(fileURLWithPath: "/tmp/devys-shared-root")
        let first = registry.makeService(rootURL: rootURL)
        let second = registry.makeService(rootURL: rootURL)
        let recorder = RecordedWatchEvents()

        first.onFileChange = { changeType, _ in
            recorder.append(("first", changeType))
        }
        second.onFileChange = { changeType, _ in
            recorder.append(("second", changeType))
        }

        first.startWatching()
        second.startWatching()

        #expect(factory.transports.count == 1)
        #expect(factory.transports.first?.startWatchingCallCount == 1)

        factory.transports.first?.emit(.modified, at: rootURL.appendingPathComponent("file.swift"))

        #expect(recorder.events.count == 2)

        first.stopWatching()
        #expect(factory.transports.first?.stopWatchingCallCount == 0)

        second.stopWatching()
        #expect(factory.transports.first?.stopWatchingCallCount == 1)
    }

    @Test("Reactivating listeners reuses the existing root watcher identity")
    func reusesRootWatcherIdentityAcrossListenerLifecycles() {
        let factory = RecordingWatchTransportFactory()
        let registry = SharedFileWatchRegistry(transportFactory: factory.make(rootURL:))
        let rootURL = URL(fileURLWithPath: "/tmp/devys-shared-root")
        let service = registry.makeService(rootURL: rootURL)

        service.startWatching()
        service.stopWatching()
        service.startWatching()

        #expect(factory.transports.count == 1)
        #expect(factory.transports.first?.startWatchingCallCount == 2)
        #expect(factory.transports.first?.stopWatchingCallCount == 1)
    }
}

private final class RecordingWatchTransportFactory {
    private(set) var transports: [RecordingWatchTransport] = []

    func make(rootURL: URL) -> FileWatchService {
        let transport = RecordingWatchTransport(rootURL: rootURL)
        transports.append(transport)
        return transport
    }
}

private final class RecordingWatchTransport: FileWatchService, @unchecked Sendable {
    let rootURL: URL
    private let lock = NSLock()

    private var onFileChangeStorage: FileChangeHandler?
    private var startWatchingCallCountStorage = 0
    private var stopWatchingCallCountStorage = 0

    init(rootURL: URL) {
        self.rootURL = rootURL
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

    var startWatchingCallCount: Int {
        lock.withLock { startWatchingCallCountStorage }
    }

    var stopWatchingCallCount: Int {
        lock.withLock { stopWatchingCallCountStorage }
    }

    func startWatching() {
        lock.withLock {
            startWatchingCallCountStorage += 1
        }
    }

    func stopWatching() {
        lock.withLock {
            stopWatchingCallCountStorage += 1
        }
    }

    func watchDirectory(_ url: URL) {
        _ = url
    }

    func unwatchDirectory(_ url: URL) {
        _ = url
    }

    func emit(_ changeType: FileChangeType, at url: URL) {
        let handler = lock.withLock { onFileChangeStorage }
        handler?(changeType, url)
    }
}

private final class RecordedWatchEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(String, FileChangeType)] = []

    var events: [(String, FileChangeType)] {
        lock.withLock { storage }
    }

    func append(_ event: (String, FileChangeType)) {
        lock.withLock {
            storage.append(event)
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
