// FileSystemWatcher.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Type of file system change detected.
public enum FileChangeType: Sendable {
    case created
    case modified
    case deleted
    case renamed
}

/// Callback type for file change notifications.
public typealias FileChangeHandler = @Sendable (FileChangeType, URL) -> Void

/// Watches directories for file system changes using DispatchSource.
///
/// This class provides real-time file system monitoring with:
/// - Per-directory watching using DispatchSource
/// - Debouncing to batch rapid changes (100ms default)
/// - Efficient FD management
public final class FileSystemWatcher: @unchecked Sendable {
    // MARK: - Properties
    
    private let rootURL: URL
    private var directorySources: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "com.devys.filewatcher", qos: .utility)
    private let lock = NSLock()
    
    /// Called when a file change is detected.
    public var onFileChange: FileChangeHandler?
    
    // MARK: - Debouncing
    
    private var pendingChanges: Set<URL> = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    
    // MARK: - Initialization
    
    /// Creates a new file system watcher.
    /// - Parameters:
    ///   - rootURL: The root directory to watch.
    ///   - debounceInterval: Interval to batch changes (default 100ms).
    public init(rootURL: URL, debounceInterval: TimeInterval = 0.1) {
        self.rootURL = rootURL
        self.debounceInterval = debounceInterval
    }
    
    deinit {
        stopWatching()
    }
    
    // MARK: - Public Methods
    
    /// Starts watching the root directory.
    public func startWatching() {
        watchDirectory(rootURL)
    }
    
    /// Stops all file watching and cleans up resources.
    public func stopWatching() {
        lock.lock()
        defer { lock.unlock() }
        
        for (_, source) in directorySources {
            source.cancel()
        }
        directorySources.removeAll()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }
    
    /// Adds a directory to the watch list.
    /// - Parameter url: The directory URL to watch.
    public func watchDirectory(_ url: URL) {
        lock.lock()
        let path = url.path
        guard directorySources[path] == nil else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange(url)
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.activate()
        
        lock.lock()
        directorySources[path] = source
        lock.unlock()
    }
    
    /// Removes a directory from the watch list.
    /// - Parameter url: The directory URL to stop watching.
    public func unwatchDirectory(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        let path = url.path
        if let source = directorySources.removeValue(forKey: path) {
            source.cancel()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleDirectoryChange(_ url: URL) {
        lock.lock()
        pendingChanges.insert(url)
        lock.unlock()
        
        debounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingChanges()
        }
        
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    private func flushPendingChanges() {
        lock.lock()
        let changes = pendingChanges
        pendingChanges.removeAll()
        lock.unlock()
        
        for changedURL in changes {
            DispatchQueue.main.async { [weak self] in
                self?.onFileChange?(.modified, changedURL)
            }
        }
    }
}
