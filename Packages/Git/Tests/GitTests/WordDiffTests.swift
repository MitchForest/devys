// WordDiffTests.swift
// Tests for word-level diff algorithm.

import Testing
@testable import Git

struct WordDiffTests {
    
    @Test func identicalLines() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "hello world",
            new: "hello world"
        )
        
        // All changes should be unchanged
        #expect(oldChanges.allSatisfy { $0.type == .unchanged })
        #expect(newChanges.allSatisfy { $0.type == .unchanged })
    }
    
    @Test func completelyDifferent() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "hello world",
            new: "foo bar"
        )
        
        // Old line should have removed changes
        #expect(oldChanges.contains { $0.type == .removed })
        
        // New line should have added changes
        #expect(newChanges.contains { $0.type == .added })
    }
    
    @Test func partialChange() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "let value = 5",
            new: "let value = 10"
        )
        
        // "let value = " should be unchanged in both
        let oldUnchanged = oldChanges.filter { $0.type == .unchanged }
        let newUnchanged = newChanges.filter { $0.type == .unchanged }
        
        #expect(!oldUnchanged.isEmpty)
        #expect(!newUnchanged.isEmpty)
        
        // "5" should be removed, "10" should be added
        let oldRemoved = oldChanges.filter { $0.type == .removed }
        let newAdded = newChanges.filter { $0.type == .added }
        
        #expect(!oldRemoved.isEmpty)
        #expect(!newAdded.isEmpty)
    }
    
    @Test func emptyLines() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "",
            new: ""
        )
        
        #expect(oldChanges.isEmpty)
        #expect(newChanges.isEmpty)
    }
    
    @Test func emptyToContent() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "",
            new: "new content"
        )
        
        #expect(oldChanges.isEmpty)
        #expect(newChanges.contains { $0.type == .added })
    }
    
    @Test func contentToEmpty() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "old content",
            new: ""
        )
        
        #expect(oldChanges.contains { $0.type == .removed })
        #expect(newChanges.isEmpty)
    }
    
    @Test func symbolChange() {
        let (_, newChanges) = WordDiff.diff(
            old: "func foo() { }",
            new: "func foo() -> Int { }"
        )
        
        // "func foo()" should be unchanged
        // "-> Int" should be added
        let newAdded = newChanges.filter { $0.type == .added }
        #expect(!newAdded.isEmpty)
    }
    
    @Test func charMode() {
        let (oldChanges, newChanges) = WordDiff.diff(
            old: "hello",
            new: "hallo",
            mode: .char
        )
        
        // 'e' should be removed, 'a' should be added
        let oldRemoved = oldChanges.filter { $0.type == .removed }
        let newAdded = newChanges.filter { $0.type == .added }
        
        #expect(oldRemoved.count == 1)
        #expect(newAdded.count == 1)
    }
}
