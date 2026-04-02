// DiffParserTests.swift
// Tests for the unified diff parser.

import Testing
@testable import Git

@MainActor
struct DiffParserTests {
    
    @Test func parseSimpleDiff() {
        let diff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,4 @@
         unchanged line
        -removed line
        +added line
        +another added line
         context line
        """
        
        let parsed = DiffParser.parse(diff)
        
        #expect(!parsed.isBinary)
        #expect(parsed.oldPath == "file.txt")
        #expect(parsed.newPath == "file.txt")
        #expect(parsed.hunks.count == 1)
        
        let hunk = parsed.hunks[0]
        #expect(hunk.oldStart == 1)
        #expect(hunk.oldCount == 3)
        #expect(hunk.newStart == 1)
        #expect(hunk.newCount == 4)
        #expect(hunk.addedCount == 2)
        #expect(hunk.removedCount == 1)
    }
    
    @Test func parseMultipleHunks() {
        let diff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,3 @@
         line 1
        -line 2
        +line 2 modified
         line 3
        @@ -10,3 +10,4 @@
         line 10
         line 11
        +new line
         line 12
        """
        
        let parsed = DiffParser.parse(diff)
        
        #expect(parsed.hunks.count == 2)
        #expect(parsed.hunks[0].oldStart == 1)
        #expect(parsed.hunks[1].oldStart == 10)
        #expect(parsed.totalAdded == 2)
        #expect(parsed.totalRemoved == 1)
    }
    
    @Test func parseBinaryFile() {
        let diff = """
        Binary files a/image.png and b/image.png differ
        """
        
        let parsed = DiffParser.parse(diff)
        
        #expect(parsed.isBinary)
        #expect(parsed.hunks.isEmpty)
    }
    
    @Test func parseNewFile() {
        let diff = """
        --- /dev/null
        +++ b/new-file.txt
        @@ -0,0 +1,3 @@
        +line 1
        +line 2
        +line 3
        """
        
        let parsed = DiffParser.parse(diff)
        
        #expect(parsed.oldPath == nil)
        #expect(parsed.newPath == "new-file.txt")
        #expect(parsed.totalAdded == 3)
        #expect(parsed.totalRemoved == 0)
    }
    
    @Test func parseDeletedFile() {
        let diff = """
        --- a/deleted.txt
        +++ /dev/null
        @@ -1,3 +0,0 @@
        -line 1
        -line 2
        -line 3
        """
        
        let parsed = DiffParser.parse(diff)
        
        #expect(parsed.oldPath == "deleted.txt")
        #expect(parsed.newPath == nil)
        #expect(parsed.totalAdded == 0)
        #expect(parsed.totalRemoved == 3)
    }
    
    @Test func parseNoNewlineAtEnd() {
        let diff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,2 +1,2 @@
         line 1
        -line 2
        \\ No newline at end of file
        +line 2 modified
        \\ No newline at end of file
        """
        
        let parsed = DiffParser.parse(diff)
        
        #expect(parsed.hunks.count == 1)
        let lines = parsed.hunks[0].lines
        let noNewlineLines = lines.filter { $0.type == .noNewline }
        #expect(noNewlineLines.count == 2)
    }
    
    @Test func lineNumbersAreCorrect() {
        let diff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -5,4 +5,5 @@
         line 5
        -line 6
        +line 6 modified
        +new line
         line 7
         line 8
        """
        
        let parsed = DiffParser.parse(diff)
        let lines = parsed.hunks[0].lines.filter { $0.type != .header }
        
        // Context line 5
        #expect(lines[0].oldLineNumber == 5)
        #expect(lines[0].newLineNumber == 5)
        
        // Removed line 6
        #expect(lines[1].oldLineNumber == 6)
        #expect(lines[1].newLineNumber == nil)
        
        // Added line
        #expect(lines[2].oldLineNumber == nil)
        #expect(lines[2].newLineNumber == 6)
        
        // Added line
        #expect(lines[3].oldLineNumber == nil)
        #expect(lines[3].newLineNumber == 7)
        
        // Context line 7/8
        #expect(lines[4].oldLineNumber == 7)
        #expect(lines[4].newLineNumber == 8)
    }
}
