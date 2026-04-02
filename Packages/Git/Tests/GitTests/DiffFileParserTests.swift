// DiffFileParserTests.swift
// Tests for splitting multi-file diffs.

import Testing
@testable import Git

@MainActor
struct DiffFileParserTests {
    @Test func splitsMultipleFiles() {
        let diff = """
        diff --git a/first.swift b/first.swift
        --- a/first.swift
        +++ b/first.swift
        @@ -1,1 +1,1 @@
        -let a = 1
        +let a = 2
        diff --git a/second.swift b/second.swift
        --- a/second.swift
        +++ b/second.swift
        @@ -1,1 +1,1 @@
        -let b = 1
        +let b = 2
        """

        let files = DiffFileParser.parseFiles(diff)
        #expect(files.count == 2)
        #expect(files[0].filePath == "first.swift")
        #expect(files[1].filePath == "second.swift")
    }
}
