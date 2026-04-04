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

    @Test func keepsRenameOnlyDiffsAndCanonicalizesPathsWithSpaces() {
        let diff = """
        diff --git a/dir with space/old name.swift b/dir with space/new name.swift
        similarity index 100%
        rename from dir with space/old name.swift
        rename to dir with space/new name.swift
        diff --git a/dir with space/file name.swift b/dir with space/file name.swift
        --- a/dir with space/file name.swift\t
        +++ b/dir with space/file name.swift\t
        @@ -1 +1 @@
        -one
        +two
        """

        let files = DiffFileParser.parseFiles(diff)

        #expect(files.count == 2)
        #expect(files[0].filePath == "dir with space/new name.swift")
        #expect(files[0].diff.oldPath == "dir with space/old name.swift")
        #expect(files[0].diff.newPath == "dir with space/new name.swift")
        #expect(files[0].diff.hasChanges)
        #expect(files[1].filePath == "dir with space/file name.swift")
        #expect(files[1].diff.oldPath == "dir with space/file name.swift")
        #expect(files[1].diff.newPath == "dir with space/file name.swift")
    }
}
