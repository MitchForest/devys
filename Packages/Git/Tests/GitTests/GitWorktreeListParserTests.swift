// GitWorktreeListParserTests.swift
// DevysGit Tests

import Testing
import Foundation
@testable import Git

@Suite("Git Worktree List Parser Tests")
struct GitWorktreeListParserTests {
    @Test("Parses basic worktree list output")
    func parsesWorktreeList() {
        let output = """
        worktree /tmp/repo
        HEAD 1234567890abcdef
        branch refs/heads/main

        worktree /tmp/repo-wt
        HEAD abcdef1234567890
        branch refs/heads/feature/test
        """

        let entries = GitWorktreeListParser.parse(output)
        #expect(entries.count == 2)
        #expect(entries[0].path == URL(fileURLWithPath: "/tmp/repo"))
        #expect(entries[0].branchName == "main")
        #expect(entries[1].path == URL(fileURLWithPath: "/tmp/repo-wt"))
        #expect(entries[1].branchName == "feature/test")
    }

    @Test("Ignores detached and bare markers")
    func ignoresDetachedAndBareMarkers() {
        let output = """
        worktree /tmp/repo
        HEAD 1234567890abcdef
        bare

        worktree /tmp/repo-wt
        HEAD abcdef1234567890
        detached
        """

        let entries = GitWorktreeListParser.parse(output)
        #expect(entries.count == 2)
        #expect(entries[0].path == URL(fileURLWithPath: "/tmp/repo"))
        #expect(entries[0].branchName == nil)
        #expect(entries[1].path == URL(fileURLWithPath: "/tmp/repo-wt"))
        #expect(entries[1].branchName == nil)
    }
}
