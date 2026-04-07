// RecursiveFileWatchServiceTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreServices
import Testing
@testable import Workspace

@Suite("RecursiveFileWatchService Tests")
struct RecursiveFileWatchServiceTests {
    @Test("decodePaths returns expected paths for CFArray pointer")
    func decodePathsCFArray() {
        let paths = ["/tmp/a", "/tmp/b"]
        let cfArray: CFArray = paths as CFArray
        let pointer = Unmanaged.passUnretained(cfArray).toOpaque()
        let decoded = RecursiveFileWatchService.decodePaths(count: paths.count, pointer: pointer)
        #expect(decoded == paths)
    }

    @Test("decodePaths clamps to the provided count")
    func decodePathsCountClamp() {
        let paths = ["/tmp/a", "/tmp/b", "/tmp/c"]
        let cfArray: CFArray = paths as CFArray
        let pointer = Unmanaged.passUnretained(cfArray).toOpaque()
        let decoded = RecursiveFileWatchService.decodePaths(count: 2, pointer: pointer)
        #expect(decoded == Array(paths.prefix(2)))
    }

    @Test("overflow-related FSEvent flags map to overflow")
    func overflowFlagsMapToOverflow() {
        let flags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagKernelDropped
        )
        #expect(RecursiveFileWatchService.changeType(from: flags) == .overflow)
    }
}
