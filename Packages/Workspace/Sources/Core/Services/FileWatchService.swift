// FileWatchService.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Abstraction for file system watching.
public protocol FileWatchService: AnyObject {
    var onFileChange: FileChangeHandler? { get set }

    func startWatching()
    func stopWatching()
    func watchDirectory(_ url: URL)
    func unwatchDirectory(_ url: URL)
}

public final class DefaultFileWatchService: FileWatchService {
    private let watcher: FileSystemWatcher

    public var onFileChange: FileChangeHandler? {
        get { watcher.onFileChange }
        set { watcher.onFileChange = newValue }
    }

    public init(rootURL: URL, debounceInterval: TimeInterval = 0.1) {
        self.watcher = FileSystemWatcher(rootURL: rootURL, debounceInterval: debounceInterval)
    }

    public func startWatching() {
        watcher.startWatching()
    }

    public func stopWatching() {
        watcher.stopWatching()
    }

    public func watchDirectory(_ url: URL) {
        watcher.watchDirectory(url)
    }

    public func unwatchDirectory(_ url: URL) {
        watcher.unwatchDirectory(url)
    }
}
