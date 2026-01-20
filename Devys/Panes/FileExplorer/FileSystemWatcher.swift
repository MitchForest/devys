import Foundation
import CoreServices

/// Watches a directory for file system changes using FSEvents.
///
/// This actor provides an async stream of file change events,
/// debouncing rapid changes to avoid flooding the UI.
public actor FileSystemWatcher {
    /// The directory being watched
    private let rootURL: URL

    /// FSEvents stream reference
    private var eventStream: FSEventStreamRef?

    /// Continuation for the async stream
    private var continuation: AsyncStream<[FileChangeEvent]>.Continuation?

    /// Pending events for debouncing
    private var pendingEvents: [FileChangeEvent] = []

    /// Debounce task
    private var debounceTask: Task<Void, Never>?

    /// Debounce interval in seconds
    private let debounceInterval: TimeInterval = 0.1

    /// Callback context for FSEvents
    private var callbackContext: UnsafeMutableRawPointer?

    // MARK: - Initialization

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    deinit {
        // Note: Actor deinit runs on actor's executor
        // We need to stop synchronously here
    }

    // MARK: - Public API

    /// Start watching and return an async stream of change events
    public func startWatching() -> AsyncStream<[FileChangeEvent]> {
        AsyncStream { continuation in
            self.continuation = continuation

            Task {
                self.setupEventStream()
            }

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.stopWatching()
                }
            }
        }
    }

    /// Stop watching for changes
    public func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil

        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }

        if let context = callbackContext {
            context.deallocate()
            callbackContext = nil
        }

        continuation?.finish()
        continuation = nil
    }

    // MARK: - FSEvents Setup

    private func setupEventStream() {
        let pathsToWatch = [rootURL.path] as CFArray

        // Create callback context with reference to self
        let contextPtr = UnsafeMutablePointer<FileSystemWatcher>.allocate(capacity: 1)
        contextPtr.initialize(to: self)
        callbackContext = UnsafeMutableRawPointer(contextPtr)

        var context = FSEventStreamContext(
            version: 0,
            info: callbackContext,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create the event stream
        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, // Latency in seconds
            flags
        ) else {
            return
        }

        eventStream = stream

        // Schedule on dispatch queue
        let queue = DispatchQueue(label: "com.devys.fsevents", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)

        FSEventStreamStart(stream)
    }

    // MARK: - Event Handling

    /// Called by FSEvents callback
    fileprivate func handleEvents(_ events: [FileChangeEvent]) {
        pendingEvents.append(contentsOf: events)

        // Cancel existing debounce task
        debounceTask?.cancel()

        // Start new debounce task
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(debounceInterval))

            guard !Task.isCancelled else { return }

            let eventsToEmit = pendingEvents
            pendingEvents = []

            if !eventsToEmit.isEmpty {
                continuation?.yield(eventsToEmit)
            }
        }
    }
}

// MARK: - FSEvents Callback

/// Global callback function for FSEvents
private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }

    let watcher = info.assumingMemoryBound(to: FileSystemWatcher.self).pointee

    // Convert paths
    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
        return
    }

    var events: [FileChangeEvent] = []

    for index in 0..<numEvents {
        let path = paths[index]
        let url = URL(fileURLWithPath: path)
        let flags = eventFlags[index]

        // Skip .git directory changes
        if path.contains("/.git/") {
            continue
        }

        let eventType = FileChangeEvent.EventType.from(flags: flags)
        events.append(FileChangeEvent(url: url, type: eventType, flags: flags))
    }

    if !events.isEmpty {
        Task {
            await watcher.handleEvents(events)
        }
    }
}

// MARK: - File Change Event

/// Represents a file system change event
public struct FileChangeEvent: Sendable {
    /// URL of the changed file/directory
    public let url: URL

    /// Type of change
    public let type: EventType

    /// Raw FSEvents flags
    public let flags: FSEventStreamEventFlags

    /// Type of file system event
    public enum EventType: Sendable {
        case created
        case modified
        case deleted
        case renamed
        case unknown

        static func from(flags: FSEventStreamEventFlags) -> EventType {
            if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                return .deleted
            }
            if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                return .renamed
            }
            if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                return .created
            }
            if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                return .modified
            }
            return .unknown
        }
    }
}
