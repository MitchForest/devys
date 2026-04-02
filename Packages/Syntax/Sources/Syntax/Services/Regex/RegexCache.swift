// RegexCache.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Caches compiled regex scanners to avoid repeated compilation costs.

import Foundation

// MARK: - Regex Cache

final class RegexCache: @unchecked Sendable {
    private struct Entry {
        let scanner: (any PatternScanner)?
        let failed: Bool
        var lastAccess: UInt64
    }

    private var storage: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0
    private let lock = NSLock()
    private let maxSize = 1024

    func scanner(for pattern: String, engine: any RegexEngine) throws -> any PatternScanner {
        if let cached = cachedEntry(for: pattern) {
            if cached.failed {
                throw RegexCacheError.compileFailed
            }
            if let scanner = cached.scanner {
                return scanner
            }
        }

        do {
            let scanner = try engine.createScanner(patterns: [pattern])
            store(pattern: pattern, scanner: scanner, failed: false)
            return scanner
        } catch {
            store(pattern: pattern, scanner: nil, failed: true)
            throw error
        }
    }

    private func cachedEntry(for pattern: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = storage[pattern] else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        storage[pattern] = entry
        return entry
    }

    private func store(pattern: String, scanner: (any PatternScanner)?, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }

        accessCounter &+= 1
        storage[pattern] = Entry(scanner: scanner, failed: failed, lastAccess: accessCounter)

        if storage.count > maxSize {
            evictOldEntries()
        }
    }

    private func evictOldEntries() {
        let sorted = storage.sorted { $0.value.lastAccess < $1.value.lastAccess }
        let removeCount = max(1, maxSize / 2)
        for (key, _) in sorted.prefix(removeCount) {
            storage.removeValue(forKey: key)
        }
    }
}

enum RegexCacheError: Error {
    case compileFailed
}
